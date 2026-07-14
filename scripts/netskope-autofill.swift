#!/usr/bin/env swift
/**
 Netskope two-step email autofill (Swift CLI)

 Port of hammer_spoon/netskope-autofill.lua v7.

   Step 1: Netskope page  → email1 → AXPress "Continue"
   Step 2: Microsoft page → email2 → Return

 Usage:
   ./scripts/netskope-autofill.swift sequence --email1 you@kkpfg.com --email2 you@phatrasec.com
   ./scripts/netskope-autofill.swift step1 --email1 you@kkpfg.com
   ./scripts/netskope-autofill.swift step2 --email2 you@phatrasec.com
   ./scripts/netskope-autofill.swift dump

 Requires: System Settings → Privacy & Security → Accessibility → Terminal (or the runner).
 */

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Config

private let appName = "Netskope Client"
private let bundleID = "com.netskope.client.Netskope-Client"

private struct Step {
    let name: String
    let email: String
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

private func dumpTree(_ root: AXUIElement, depth: Int = 0, maxDepth: Int = 8) {
    guard depth <= maxDepth else { return }
    let indent = String(repeating: "  ", count: depth)
    let role = axString(root, kAXRoleAttribute as String)
    let title = axString(root, kAXTitleAttribute as String)
    let desc = axString(root, kAXDescriptionAttribute as String)
    let value = axString(root, kAXValueAttribute as String)
    var parts = [role]
    if !title.isEmpty { parts.append("title=\(title)") }
    if !desc.isEmpty { parts.append("desc=\(desc)") }
    if !value.isEmpty {
        let clipped = value.count > 60 ? String(value.prefix(60)) + "…" : value
        parts.append("value=\(clipped)")
    }
    if role == "AXButton" {
        parts.append("enabled=\(axBool(root, kAXEnabledAttribute as String))")
    }
    print("\(indent)\(parts.joined(separator: " "))")
    for child in axChildren(root) {
        dumpTree(child, depth: depth + 1, maxDepth: maxDepth)
    }
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
    typeText(step.email, to: pid)
    log("\(step.name): typed email")

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

private func waitThenRunStep2(_ step2: Step) {
    var elapsed = 0.0
    while elapsed < 20.0 {
        Thread.sleep(forTimeInterval: 0.3)
        elapsed += 0.3
        if microsoftPageVisible() {
            log("Microsoft page detected after \(String(format: "%.1f", elapsed))s")
            Thread.sleep(forTimeInterval: 0.4)
            runStep(step2)
            return
        }
    }
    log("Microsoft page not detected in 20s, running step 2 anyway")
    runStep(step2)
}

private func runSequence(step1: Step, step2: Step) {
    Thread.sleep(forTimeInterval: 1.0)
    runStep(step1)
    Thread.sleep(forTimeInterval: 1.5)
    waitThenRunStep2(step2)
}

private func dumpAX() {
    guard let app = netskopeApp() else {
        log("Netskope Client not running")
        exit(1)
    }
    guard let window = focusedOrMainWindow(for: app) else {
        log("no Netskope window")
        exit(1)
    }
    let title = axString(window, kAXTitleAttribute as String)
    print("=== Netskope window: \(title) pid=\(app.processIdentifier) ===")
    dumpTree(window)
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

// MARK: - CLI

private struct Args {
    var command = "sequence"
    var email1 = "you@kkpfg.com"
    var email2 = "you@phatrasec.com"
    var password = ""
}

private func parseArgs(dotEnv: [String: String]) -> Args {
    var args = Args()
    args.email1 = envValue("NETSKOPE_EMAIL", file: dotEnv,
                           fallback: envValue("NETSKOPE_EMAIL1", file: dotEnv, fallback: args.email1))
    args.email2 = envValue("KKPS_EMAIL", file: dotEnv,
                           fallback: envValue("NETSKOPE_EMAIL2", file: dotEnv, fallback: args.email2))
    args.password = envValue("KKPS_PASSWORD", file: dotEnv)

    let argv = Array(CommandLine.arguments.dropFirst())
    var i = 0
    if let first = argv.first, !first.hasPrefix("-") {
        args.command = first
        i = 1
    }
    while i < argv.count {
        let a = argv[i]
        defer { i += 1 }
        switch a {
        case "--email1":
            i += 1
            if i < argv.count { args.email1 = argv[i] }
        case "--email2":
            i += 1
            if i < argv.count { args.email2 = argv[i] }
        case "-h", "--help":
            print("""
            Usage: netskope-autofill.swift <sequence|step1|step2|dump|env> [--email1 E] [--email2 E]

            Loads project-root .env:
              NETSKOPE_EMAIL   first page (Netskope)
              KKPS_EMAIL       second page (Microsoft / KKPS)
              KKPS_PASSWORD    available to the script (not typed yet)
            CLI flags override .env / environment.
            Command `env` only prints loaded values (no Accessibility needed).
            """)
            exit(0)
        default:
            log("unknown argument: \(a)")
            exit(2)
        }
    }
    return args
}

// MARK: - Main

private func main() {
    let loaded = loadDotEnv()
    if let path = loaded.path {
        log("loaded .env from \(path)")
    } else {
        log("no .env found (cwd=\(FileManager.default.currentDirectoryPath))")
    }

    let args = parseArgs(dotEnv: loaded.values)
    log("NETSKOPE_EMAIL=\(args.email1)")
    log("KKPS_EMAIL=\(args.email2)")
    log("KKPS_PASSWORD=\(args.password.isEmpty ? "(empty)" : "(set)")")

    if args.command != "env" {
        requireAccessibility()
    }

    let step1 = Step(
        name: "step1",
        email: args.email1,
        buttonPattern: "continue",
        fieldX: 0.50, fieldY: 0.68,
        buttonX: 0.50, buttonY: 0.78
    )
    let step2 = Step(
        name: "step2",
        email: args.email2,
        buttonPattern: nil,
        fieldX: 0.50, fieldY: 0.24,
        buttonX: 0.50, buttonY: 0.50
    )

    switch args.command {
    case "env":
        // Already logged above; nothing else to do.
        break
    case "dump":
        dumpAX()
    case "step1":
        runStep(step1)
    case "step2":
        runStep(step2)
    case "sequence":
        runSequence(step1: step1, step2: step2)
    default:
        log("unknown command: \(args.command) (use sequence|step1|step2|dump|env)")
        exit(2)
    }

    log("done")
}

main()
