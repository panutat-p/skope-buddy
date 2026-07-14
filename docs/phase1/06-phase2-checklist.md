# Phase 2 Implementation Checklist

**Phase:** 2 goal — build the native menu-bar app skeleton and autofill engine per Phase 1 docs.  
**Out of Phase 2:** polished marketing UI, public distribution website, MFA automation.

## 0. Prerequisites (from Phase 1)

- [x] Functional requirements written
- [x] Accessibility findings documented
- [x] ADR accepted
- [x] Permission / distribution plan written
- [x] Test scenarios defined
- [ ] Live AX dumps attached during first real re-authenticate session (complete early in Phase 2)

## 1. Xcode project bootstrap

- [ ] Create macOS App target (Swift, AppKit or AppKit + SwiftUI Settings)
- [ ] Set bundle ID (stable), deployment target **macOS 14**
- [ ] Disable App Sandbox; enable Hardened Runtime
- [ ] Add `LSUIElement` / menu-bar agent lifecycle (no Dock icon)
- [ ] Wire Debug/Release schemes; `.gitignore` for `xcuserdata`, build products

## 2. Core modules

- [ ] `NetskopeAppResolver` — locate running `com.netskope.client.Netskope-Client` / “Netskope Client”
- [ ] `AXTree` — DFS walker; safe string coercion; find text fields & buttons by predicate
- [ ] `PageDetector` — Step1 (Continue) vs Step2 (Next / Sign in)
- [ ] `KeystrokePoster` — `Cmd+A`, type string, Return; **post to Netskope PID**
- [ ] `ContinuePress` — poll `AXEnabled`, `AXPress`, coordinate fallback flag
- [ ] `LoginStateMachine` — states from FR-8; single-flight; 30s cooldown; 20s Microsoft wait
- [ ] `WindowWatcher` — subscribe to Netskope window appear/focus; debounce into state machine
- [ ] `EmailStore` — UserDefaults read/write for email1 / email2
- [ ] `AccessibilityGate` — trust check, Settings deep link, status for UI
- [ ] `Logger` — rotating file + OSLog; redact options

## 3. Menu-bar interface (minimal)

- [ ] Status item with state-aware title/image
- [ ] Menu: Run Sequence, Step 1, Step 2, Settings…, Open Logs, Launch at Login toggle, Quit
- [ ] Settings: email1, email2, enable auto-run, enable hotkeys, reveal log folder
- [ ] Optional hotkeys ⌘⌥1 / ⌘⌥2 (match Hammerspoon)

## 4. Permissions & login item

- [ ] Prompt / guide Accessibility on first need
- [ ] Block automation when untrusted
- [ ] `SMAppService` launch-at-login toggle (default off)

## 5. Validation against Hammerspoon parity

- [ ] Capture live AX dumps; update `02-accessibility-findings.md`
- [ ] Run S01–S03, S10–S13, S20–S22, S30–S35, S40–S43 from `05-test-scenarios.md`
- [ ] Compare behavior with Hammerspoon v7 on the same re-auth prompt (side-by-side once)
- [ ] Confirm Enter is **not** used for Step 1; **is** used for Step 2

## 6. Packaging prep (not full rollout)

- [ ] Archive signed Debug/Release with Developer ID (when cert available)
- [ ] Smoke notarization on a release candidate
- [ ] Draft IT allowlist blurb (bundle ID, team ID, purpose)

## 7. Exit criteria for Phase 2 → Phase 3

- [ ] Happy path works without Hammerspoon loaded
- [ ] P1 acceptance criteria S13/S21/S31–S34/S40–S42 pass
- [ ] No password/MFA handling introduced
- [ ] README for local run + Accessibility setup

## Suggested Phase 3+ (not started)

- Polish UI, icons, onboarding screenshots
- Coordinated Jamf pkg + EDR allowlist
- Telemetry opt-in for failure rates (no email content)
- Handle Netskope UI regressions / multi-field forms
