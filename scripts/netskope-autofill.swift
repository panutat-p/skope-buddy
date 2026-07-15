#!/usr/bin/env swift
/**
 Netskope two-step email autofill (Swift CLI)

 Native implementation: macOS Accessibility (AX) API for discovery/focus/press,
 CGEvents posted to the Netskope process for keystrokes. No external dependencies.

   Step 1: Netskope page  → email1   → AXPress "Continue"
   Step 2: Microsoft page → email2   → Return
   Step 3: Password page  → password → AXPress "Sign in"

 MFA approval, if prompted after step 3, stays manual — never automated here.

 Usage:
   ./scripts/netskope-autofill.swift

 Requires: System Settings → Privacy & Security → Accessibility → Terminal (or the runner).
   Credentials from project-root .env (NETSKOPE_EMAIL, CORPORATE_EMAIL, CORPORATE_PASSWORD).
 */

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Config

private let appName = "Netskope Client"
private let bundleID = "com.netskope.client.Netskope-Client"
/// After a sequence attempt, suppress re-triggers long enough to absorb
/// leftover window events and MFA (matches Phase 1 cooldown).
private let sequenceCooldownSeconds: TimeInterval = 30
/// How long to sleep between idle wake checks when no UI event arrives.
/// Tuned for rare prompts (≈2×/day); AX work only runs after a wake.
private let idleSafetyPollSeconds: TimeInterval = 60
/// After a wake, poll briefly while the re-auth webview finishes loading.
private let activeBurstSeconds: TimeInterval = 20
private let activePollInterval: TimeInterval = 0.5

private struct Step {
    let name: String
    let value: String
    let buttonPattern: String? // nil → submit with Return
    let fieldX: CGFloat
    let fieldY: CGFloat
    let buttonX: CGFloat
    let buttonY: CGFloat
    var useEnter: Bool { buttonPattern == nil }
}

// MARK: - Logging

private func log(_ message: String) {
    FileHandle.standardError.write(Data("[netskope-autofill] \(message)\n".utf8))
}

// MARK: - Accessibility helpers

private func requireAccessibility() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(opts) else {
        log("Accessibility not granted. Enable this terminal (or binary) in System Settings → Privacy & Security → Accessibility.")
        exit(1)
    }
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value else { return "" }
    if let s = value as? String { return s }
    if let s = value as? NSString { return s as String }
    return String(describing: value)
}

private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return false
    }
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.boolValue }
    return false
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let array = value as? [AnyObject] else { return [] }
    return array.map { unsafeBitCast($0, to: AXUIElement.self) }
}

private func findElement(
    _ root: AXUIElement,
    depth: Int = 0,
    match: (AXUIElement, String) -> Bool
) -> AXUIElement? {
    guard depth <= 25 else { return nil }
    let role = axString(root, kAXRoleAttribute as String)
    if !role.isEmpty, match(root, role) { return root }
    for child in axChildren(root) {
        if let found = findElement(child, depth: depth + 1, match: match) {
            return found
        }
    }
    return nil
}

// MARK: - App / window

private func netskopeApp() -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    if let byBundle = running.first(where: { $0.bundleIdentifier == bundleID }) {
        return byBundle
    }
    return running.first(where: { $0.localizedName == appName })
}

private func focusedOrMainWindow(for app: NSRunningApplication) -> AXUIElement? {
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var focused: AnyObject?
    if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focused) == .success,
       let win = focused {
        return unsafeBitCast(win, to: AXUIElement.self)
    }
    var windows: AnyObject?
    if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windows) == .success,
       let list = windows as? [AnyObject], !list.isEmpty {
        // Prefer a re-authenticate window when several exist.
        for item in list {
            let win = unsafeBitCast(item, to: AXUIElement.self)
            let title = axString(win, kAXTitleAttribute as String).lowercased()
            if title.contains("re-authenticate") || title.contains("sign in") {
                return win
            }
        }
        return unsafeBitCast(list[0], to: AXUIElement.self)
    }
    return nil
}

private func windowFrame(_ window: AXUIElement) -> CGRect? {
    var positionValue: AnyObject?
    var sizeValue: AnyObject?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
    else { return nil }

    var position = CGPoint.zero
    var size = CGSize.zero
    let posOK = AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
    let sizeOK = AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    guard posOK, sizeOK else { return nil }
    return CGRect(origin: position, size: size)
}

private func focusWindow(_ window: AXUIElement, app: NSRunningApplication) {
    app.activate()
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
}

// MARK: - Input (process-targeted)

private func postKey(pid: pid_t, keyCode: CGKeyCode, flags: CGEventFlags = [], hold: TimeInterval = 0.02) {
    let source = CGEventSource(stateID: .hidSystemState)
    if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
        down.flags = flags
        down.postToPid(pid)
    }
    Thread.sleep(forTimeInterval: hold)
    if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
        up.flags = flags
        up.postToPid(pid)
    }
}

private func typeText(_ text: String, to pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    for scalar in text.unicodeScalars {
        var chars = [UniChar](String(scalar).utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        up?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        down?.postToPid(pid)
        up?.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.012)
    }
}

private func leftClick(at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    if let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                          mouseCursorPosition: point, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
    }
    Thread.sleep(forTimeInterval: 0.05)
    if let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                        mouseCursorPosition: point, mouseButton: .left) {
        up.post(tap: .cghidEventTap)
    }
}

private func clickFraction(window: AXUIElement, fx: CGFloat, fy: CGFloat) {
    guard let frame = windowFrame(window) else {
        log("clickFraction: no window frame")
        return
    }
    let point = CGPoint(x: frame.minX + frame.width * fx, y: frame.minY + frame.height * fy)
    leftClick(at: point)
}

// MARK: - Steps

private func runStep(_ step: Step) {
    guard let app = netskopeApp() else {
        log("\(step.name): Netskope Client not running")
        return
    }
    guard let window = focusedOrMainWindow(for: app) else {
        log("\(step.name): no Netskope window")
        return
    }

    let title = axString(window, kAXTitleAttribute as String)
    log("\(step.name): starting, window=\(title.isEmpty ? "(untitled)" : title)")
    focusWindow(window, app: app)
    Thread.sleep(forTimeInterval: 0.4)

    let field = findElement(window) { _, role in
        role == "AXTextField" || role == "AXTextArea"
    }

    var button: AXUIElement?
    if let pattern = step.buttonPattern {
        button = findElement(window) { el, role in
            guard role == "AXButton" else { return false }
            let label = (axString(el, kAXTitleAttribute as String) + " "
                + axString(el, kAXDescriptionAttribute as String)).lowercased()
            return label.contains(pattern)
        }
    }

    if let field {
        log("\(step.name): AX focusing field")
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    } else {
        log("\(step.name): no AX field, clicking position")
        clickFraction(window: window, fx: step.fieldX, fy: step.fieldY)
    }

    Thread.sleep(forTimeInterval: 0.4)
    let pid = app.processIdentifier
    // Cmd+A (virtual key 0 = 'a')
    postKey(pid: pid, keyCode: 0, flags: .maskCommand)
    Thread.sleep(forTimeInterval: 0.05)
    typeText(step.value, to: pid)
    log("\(step.name): typed value")

    if step.useEnter {
        Thread.sleep(forTimeInterval: 0.6)
        log("\(step.name): submitting with Enter")
        postKey(pid: pid, keyCode: 36) // Return
        return
    }

    var attempts = 0
    while attempts < 8 {
        attempts += 1
        Thread.sleep(forTimeInterval: 0.4)
        let enabled = button.map { axBool($0, kAXEnabledAttribute as String) } ?? false
        if enabled, let button {
            log("\(step.name): AX pressing '\(step.buttonPattern ?? "")'")
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            return
        }
    }

    log("\(step.name): fallback click on button position")
    clickFraction(window: window, fx: step.buttonX, fy: step.buttonY)
}

private func microsoftPageVisible() -> Bool {
    guard let app = netskopeApp(), let window = focusedOrMainWindow(for: app) else {
        return false
    }
    return findElement(window) { el, role in
        if role == "AXButton" {
            let t = (axString(el, kAXTitleAttribute as String) + " "
                + axString(el, kAXDescriptionAttribute as String)).lowercased()
            if t.contains("next") { return true }
        }
        if role == "AXStaticText" || role == "AXHeading" {
            let v = (axString(el, kAXValueAttribute as String) + " "
                + axString(el, kAXTitleAttribute as String)).lowercased()
            if v.contains("sign in") { return true }
        }
        return false
    } != nil
}

private func passwordPageVisible() -> Bool {
    guard let app = netskopeApp(), let window = focusedOrMainWindow(for: app) else {
        return false
    }
    return findElement(window) { el, role in
        guard role == "AXTextField" || role == "AXStaticText" || role == "AXHeading" else { return false }
        let v = (axString(el, kAXTitleAttribute as String) + " "
            + axString(el, kAXDescriptionAttribute as String) + " "
            + axString(el, kAXValueAttribute as String)).lowercased()
        return v.contains("password")
    } != nil
}

/// Step 1 is ready when the Netskope window exists *and* its webview shows the
/// distinctive page-1 signature: an editable field **and** a "Continue" button.
///
/// We require the Continue button, not just any field, so this can't false-match
/// the Microsoft (step 2) or password (step 3) pages — those also have input
/// fields, and matching a field alone would let `step1` type email1 into the
/// wrong page if the script were started mid-flow. `continue` is page 1's unique
/// marker (FR-2). Both must be present because the webview populates
/// asynchronously after the window appears — waiting on real elements rather
/// than a fixed delay is what makes "start the script, then open Netskope" safe.
private func step1PageReady() -> Bool {
    guard let app = netskopeApp(), let window = focusedOrMainWindow(for: app) else {
        return false
    }
    let hasField = findElement(window) { _, role in
        role == "AXTextField" || role == "AXTextArea"
    } != nil
    guard hasField else { return false }

    let hasContinue = findElement(window) { el, role in
        guard role == "AXButton" else { return false }
        let label = (axString(el, kAXTitleAttribute as String) + " "
            + axString(el, kAXDescriptionAttribute as String)).lowercased()
        return label.contains("continue")
    } != nil
    return hasContinue
}

/// Waits for the Microsoft page and runs step 2. Returns false (without typing
/// anything) if the page never appeared — typing email2 into whatever page
/// *is* showing after a timeout risks submitting it to the wrong form.
private func waitThenRunStep2(_ step2: Step) -> Bool {
    var elapsed = 0.0
    while elapsed < 20.0 {
        Thread.sleep(forTimeInterval: 0.3)
        elapsed += 0.3
        if microsoftPageVisible() {
            log("Microsoft page detected after \(String(format: "%.1f", elapsed))s")
            Thread.sleep(forTimeInterval: 0.4)
            runStep(step2)
            return true
        }
    }
    log("Microsoft page not detected in 20s, aborting step 2")
    return false
}

/// Waits for the password page and runs step 3. Same reasoning as
/// waitThenRunStep2: never type the password into an undetected page.
private func waitThenRunStep3(_ step3: Step) -> Bool {
    var elapsed = 0.0
    while elapsed < 20.0 {
        Thread.sleep(forTimeInterval: 0.3)
        elapsed += 0.3
        if passwordPageVisible() {
            log("Password page detected after \(String(format: "%.1f", elapsed))s")
            Thread.sleep(forTimeInterval: 0.4)
            runStep(step3)
            return true
        }
    }
    log("Password page not detected in 20s, aborting step 3")
    return false
}

/// Waits until the step 1 page is present, then runs step 1.
///
/// Idle path sleeps until an NSWorkspace / AX window event (or a 60s safety
/// timeout). Only event wakes get a short burst poll while the webview settles;
/// safety timeouts do a single cheap check. Avoids continuous AX walks —
/// appropriate for rare re-auth (≈2×/day, ~6h sessions).
private func waitForStep1(_ step1: Step) {
    let wake = NetskopeWakeSource.shared

    while true {
        if tryRunStep1IfReady(step1) { return }

        // Log idle only when we actually block. A pending startup poke must not
        // print "idle — sleeping" and then return immediately.
        let result = wake.wait(timeout: idleSafetyPollSeconds) {
            log("idle — waiting for Netskope re-authenticate (wake on window event, safety poll \(Int(idleSafetyPollSeconds))s)")
            MenuBarStatus.shared.set(.idle)
        }

        if result.fromEvent {
            MenuBarStatus.shared.set(.watching)
        }
        if tryRunStep1IfReady(step1) { return }

        guard result.fromEvent else { continue }

        // Webview often populates after the window event — burst-poll briefly.
        let burstDeadline = Date().addingTimeInterval(activeBurstSeconds)
        while Date() < burstDeadline {
            if tryRunStep1IfReady(step1) { return }
            Thread.sleep(forTimeInterval: activePollInterval)
        }
    }
}

private func tryRunStep1IfReady(_ step1: Step) -> Bool {
    guard step1PageReady() else { return false }
    MenuBarStatus.shared.set(.watching)
    log("step 1 page ready")
    Thread.sleep(forTimeInterval: 0.4)
    runStep(step1)
    return true
}

/// One pass: wait for step 1, then step 2 / step 3. Returns false if a later
/// step's page never appeared (nothing typed blind).
private func runSequenceOnce(step1: Step, step2: Step, step3: Step) -> Bool {
    waitForStep1(step1)
    MenuBarStatus.shared.set(.watching)
    Thread.sleep(forTimeInterval: 1.5)
    guard waitThenRunStep2(step2) else { return false }
    return waitThenRunStep3(step3)
}

/// Standing watcher: run the full sequence whenever the Netskope re-authenticate
/// page appears, cool down, then sleep again. Never returns — stop with Ctrl+C
/// or Quit from the menu-bar icon.
private func watchSequence(step1: Step, step2: Step, step3: Step) -> Never {
    log("watching for Netskope re-authenticate — Ctrl+C or Quit to stop")
    while true {
        if runSequenceOnce(step1: step1, step2: step2, step3: step3) {
            log("sequence done; cooling down \(Int(sequenceCooldownSeconds))s before idle again")
            MenuBarStatus.shared.set(.idle)
        } else {
            log("sequence incomplete; cooling down \(Int(sequenceCooldownSeconds))s before idle again")
            MenuBarStatus.shared.set(.idle)
        }
        Thread.sleep(forTimeInterval: sequenceCooldownSeconds)
    }
}

// MARK: - Idle wake source (NSWorkspace + AXObserver)

/// Blocks the watcher thread until Netskope may have shown a new window.
/// Events run on the main run loop; the watcher sleeps on an NSCondition.
private final class NetskopeWakeSource: NSObject {
    struct WaitResult {
        /// True if poke() caused the wake (worth a burst poll).
        let fromEvent: Bool
        /// True if this call blocked on the condition (vs consuming a pending poke).
        let didSleep: Bool
    }

    static let shared = NetskopeWakeSource()

    private let condition = NSCondition()
    private var signaled = false
    private var axObserver: AXObserver?
    private var observingPID: pid_t = 0
    private var workspaceTokens: [NSObjectProtocol] = []
    private var started = false

    func start() {
        precondition(Thread.isMainThread)
        guard !started else { return }
        started = true

        let nc = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, self.isNetskope(note) else { return }
                log("Netskope Client launched — attaching window observer")
                self.attachAXObserverIfNeeded()
                self.poke()
            },
            nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, self.isNetskope(note) else { return }
                self.attachAXObserverIfNeeded()
                self.poke()
            },
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, self.isNetskope(note) else { return }
                log("Netskope Client quit — detaching window observer")
                self.detachAXObserver()
            },
        ]

        attachAXObserverIfNeeded()
        if netskopeApp() != nil {
            poke() // re-auth window may already be open — pending check, not idle sleep
        }
        log("idle wake source started (NSWorkspace + AX window events)")
    }

    /// Sleep until poke() or `timeout` elapses.
    /// `beforeSleep` runs only when this call will actually block (not when a
    /// poke is already pending, e.g. startup with Netskope already running).
    @discardableResult
    func wait(timeout: TimeInterval, beforeSleep: (() -> Void)? = nil) -> WaitResult {
        condition.lock()
        if signaled {
            signaled = false
            condition.unlock()
            return WaitResult(fromEvent: true, didSleep: false)
        }
        condition.unlock()

        beforeSleep?()

        condition.lock()
        defer { condition.unlock() }
        if signaled {
            // Poked while beforeSleep ran — still didn't block.
            signaled = false
            return WaitResult(fromEvent: true, didSleep: false)
        }
        _ = condition.wait(until: Date().addingTimeInterval(timeout))
        let fromEvent = signaled
        signaled = false
        return WaitResult(fromEvent: fromEvent, didSleep: true)
    }

    func poke() {
        condition.lock()
        signaled = true
        condition.signal()
        condition.unlock()
    }

    private func isNetskope(_ note: Notification) -> Bool {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return false
        }
        return app.bundleIdentifier == bundleID || app.localizedName == appName
    }

    private func attachAXObserverIfNeeded() {
        guard let app = netskopeApp() else {
            detachAXObserver()
            return
        }
        let pid = app.processIdentifier
        if axObserver != nil, observingPID == pid { return }
        detachAXObserver()

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success,
              let observer else {
            log("AXObserverCreate failed for pid=\(pid)")
            return
        }

        let appEl = AXUIElementCreateApplication(pid)
        let notifications = [
            kAXWindowCreatedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXMainWindowChangedNotification as String,
        ]
        for name in notifications {
            let err = AXObserverAddNotification(observer, appEl, name as CFString, refcon)
            if err != .success && err != .notificationAlreadyRegistered {
                log("AXObserverAddNotification(\(name)) failed: \(err.rawValue)")
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observingPID = pid
        log("AXObserver attached to Netskope pid=\(pid)")
    }

    private func detachAXObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        axObserver = nil
        observingPID = 0
    }
}

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<NetskopeWakeSource>.fromOpaque(refcon).takeUnretainedValue().poke()
}

// MARK: - Menu bar indicator

/// Idle = indigo moon.zzz; watching = yellow bolt (SF Symbol palette, not template).
private final class MenuBarStatus {
    enum State {
        case idle
        case watching

        var symbolName: String {
            switch self {
            case .idle: "moon.zzz.fill"
            case .watching: "bolt.fill"
            }
        }

        var paletteColor: NSColor {
            switch self {
            case .idle: .systemIndigo
            case .watching: .systemYellow
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .idle: "Skope Buddy idle"
            case .watching: "Skope Buddy watching"
            }
        }

        var toolTip: String {
            switch self {
            case .idle: "Skope Buddy — idle"
            case .watching: "Skope Buddy — watching"
            }
        }
    }

    static let shared = MenuBarStatus()

    private var statusItem: NSStatusItem?
    private var state: State = .idle
    private var images: [State: NSImage] = [:]

    func attach(_ item: NSStatusItem) {
        precondition(Thread.isMainThread)
        statusItem = item
        images[.idle] = Self.makeImage(for: .idle)
        images[.watching] = Self.makeImage(for: .watching)
        apply(state)
    }

    func set(_ newState: State) {
        let applyOnMain = { [weak self] in
            guard let self else { return }
            guard self.state != newState else { return }
            self.state = newState
            self.apply(newState)
        }
        if Thread.isMainThread {
            applyOnMain()
        } else {
            // Sync so the tray updates before the watcher continues AX work.
            DispatchQueue.main.sync(execute: applyOnMain)
        }
    }

    private func apply(_ state: State) {
        guard let button = statusItem?.button else { return }
        button.image = images[state] ?? Self.makeImage(for: state)
        button.toolTip = state.toolTip
        // Palette-colored symbols must not be templates or the menu bar
        // flattens them to monochrome.
        button.image?.isTemplate = false
        button.contentTintColor = nil
    }

    private static func makeImage(for state: State) -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: state.symbolName,
            accessibilityDescription: state.accessibilityDescription
        ) else { return nil }

        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [state.paletteColor])
        return symbol
            .withSymbolConfiguration(sizeConfig)?
            .withSymbolConfiguration(colorConfig)
    }
}

/// Standing menu-bar accessory for the process lifetime.
private func runWithMenuBarIcon(_ work: @escaping () -> Int32) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // no Dock icon

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    MenuBarStatus.shared.attach(statusItem)

    let menu = NSMenu()
    let quit = NSMenuItem(
        title: "Quit Skope Buddy",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    quit.target = app
    menu.addItem(quit)
    statusItem.menu = menu

    NetskopeWakeSource.shared.start()

    DispatchQueue.global(qos: .utility).async {
        let code = work()
        DispatchQueue.main.async { exit(code) }
    }

    app.run()
    exit(0)
}

// MARK: - .env

/// Resolve project-root `.env` (cwd, parent of cwd, or parent of script/binary).
private func findDotEnvURL() -> URL? {
    let fm = FileManager.default
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
    var candidates: [URL] = [
        cwd.appendingPathComponent(".env"),
        cwd.deletingLastPathComponent().appendingPathComponent(".env"),
    ]

    let argv0 = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let scriptDir = argv0.deletingLastPathComponent()
    candidates.append(scriptDir.appendingPathComponent(".env"))
    candidates.append(scriptDir.deletingLastPathComponent().appendingPathComponent(".env"))

    // Walk up a few levels from cwd (run from scripts/ or nested dirs).
    var dir = cwd
    for _ in 0..<4 {
        candidates.append(dir.appendingPathComponent(".env"))
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent
    }

    var seen = Set<String>()
    for url in candidates {
        let path = url.standardizedFileURL.path
        guard seen.insert(path).inserted else { continue }
        if fm.isReadableFile(atPath: path) { return url.standardizedFileURL }
    }
    return nil
}

/// Parse KEY=VALUE lines. Returns the map and the file path used.
private func loadDotEnv() -> (values: [String: String], path: String?) {
    guard let url = findDotEnvURL() else {
        return ([:], nil)
    }
    guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
        return ([:], url.path)
    }

    var values: [String: String] = [:]
    for line in raw.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
        var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        values[key] = value
        // Keep process env in sync for any code that reads getenv / environment later.
        if getenv(key) == nil {
            setenv(key, value, 0)
        }
    }
    return (values, url.path)
}

private func envValue(_ key: String, file: [String: String], fallback: String = "") -> String {
    if let v = getenv(key).map({ String(cString: $0) }), !v.isEmpty { return v }
    if let v = file[key], !v.isEmpty { return v }
    return fallback
}

// MARK: - Credentials

private let placeholderEmail1 = "you@kkpfg.com"
private let placeholderEmail2 = "you@phatrasec.com"

private struct Credentials {
    var email1: String
    var email2: String
    var password: String
}

private func loadCredentials(dotEnv: [String: String]) -> Credentials {
    Credentials(
        email1: envValue("NETSKOPE_EMAIL", file: dotEnv,
                         fallback: envValue("NETSKOPE_EMAIL1", file: dotEnv, fallback: placeholderEmail1)),
        email2: envValue("CORPORATE_EMAIL", file: dotEnv,
                         fallback: envValue("NETSKOPE_EMAIL2", file: dotEnv, fallback: placeholderEmail2)),
        password: envValue("CORPORATE_PASSWORD", file: dotEnv)
    )
}

/// Refuse to type placeholder/empty emails, or an empty password, into a real
/// login page.
private func validateCredentials(_ creds: Credentials) -> Bool {
    var problems: [String] = []
    if creds.email1.isEmpty || creds.email1 == placeholderEmail1 {
        problems.append("email1 is empty or still the placeholder (\(placeholderEmail1)) — set NETSKOPE_EMAIL in .env")
    }
    if creds.email2.isEmpty || creds.email2 == placeholderEmail2 {
        problems.append("email2 is empty or still the placeholder (\(placeholderEmail2)) — set CORPORATE_EMAIL in .env")
    }
    if creds.password.isEmpty {
        problems.append("password is empty — set CORPORATE_PASSWORD in .env")
    }
    for p in problems { log(p) }
    return problems.isEmpty
}

// MARK: - Main

private func main() {
    let loaded = loadDotEnv()
    if let path = loaded.path {
        log("loaded .env from \(path)")
    } else {
        log("no .env found (cwd=\(FileManager.default.currentDirectoryPath))")
    }

    let creds = loadCredentials(dotEnv: loaded.values)
    log("NETSKOPE_EMAIL=\(creds.email1)")
    log("CORPORATE_EMAIL=\(creds.email2)")
    log("CORPORATE_PASSWORD=\(creds.password.isEmpty ? "(empty)" : "(set)")")

    requireAccessibility()

    if !validateCredentials(creds) {
        exit(1)
    }

    let step1 = Step(
        name: "step1",
        value: creds.email1,
        buttonPattern: "continue",
        fieldX: 0.50, fieldY: 0.68,
        buttonX: 0.50, buttonY: 0.78
    )
    let step2 = Step(
        name: "step2",
        value: creds.email2,
        buttonPattern: nil,
        fieldX: 0.50, fieldY: 0.24,
        buttonX: 0.50, buttonY: 0.50
    )
    // Field/button fractions are an unverified approximation copied from step1's
    // layout (same field-then-button shape) — only used as a last-resort click
    // fallback; AX-based discovery is primary and doesn't depend on them.
    let step3 = Step(
        name: "step3",
        value: creds.password,
        buttonPattern: "sign in",
        fieldX: 0.50, fieldY: 0.68,
        buttonX: 0.50, buttonY: 0.78
    )

    // Never returns — menu-bar icon stays up for the watcher lifetime.
    runWithMenuBarIcon {
        watchSequence(step1: step1, step2: step2, step3: step3)
    }
}

main()
