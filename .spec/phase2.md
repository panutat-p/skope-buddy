# Phase 2 — Implementation and Enhancements

**Status:** In progress (interim CLI shipped; native app not started)
**Goal:** build the native menu-bar app and autofill engine per [phase1.md](phase1.md).
**Out of scope:** polished marketing UI, public distribution site, MFA automation.

This is the live checklist for all open work. Design record: [phase1.md](phase1.md).

## Interim CLI script (`scripts/netskope-autofill.swift`)

The current working tool ahead of the full app.

- [x] Refuse to run with a placeholder/empty email — validate before typing into a real login page
- [x] Abort step 2 (instead of typing blind) if the Microsoft page isn't detected within the 20s timeout; propagate a real exit code
- [x] Add step 3 (password page → type `CORPORATE_PASSWORD` → AXPress "Sign in"), gated by the same validate-before-type guard; abort (don't type blind) if the password page isn't detected within 20s
- [x] Poll for the step 1 page instead of a one-shot check, so the script can be started *before* Netskope is open; waits indefinitely (Ctrl+C to cancel). Standalone `step2`/`step3` now also wait for their page instead of firing once.
- [x] Make step 1 detection distinctive (require the "Continue" button **and** a text field, not just any field) so it can't false-match the Microsoft/password pages and type email1 into the wrong page if started mid-flow
- [ ] Re-find the "Continue" button inside the retry loop — the webview can re-render after typing, invalidating the `AXUIElement` captured before typing
- [ ] Skip straight to the coordinate fallback when no button was found at all, instead of spinning through all 8 retry attempts
- [ ] Propagate real exit codes for "Netskope Client not running" / "no Netskope window" cases in `runStep`
- [ ] Replace hardcoded US-layout `Cmd+A` (virtual key 0) with `AXSelectedTextRange` or clearing via `AXValue` before typing
- [ ] Re-read window frame and verify frontmost immediately before a fallback coordinate click (window may have moved/changed)
- [ ] Restrict `.env` lookup away from world-writable directories (e.g. `/tmp`), or add an explicit `--env PATH` flag
- [ ] Only log emails under `env` / `--verbose`, not on every run
- [ ] Add a `--depth N` flag to `dump` (default depth 8 can be too shallow for nested webviews)
- [ ] Extract magic numbers (sleep intervals, retry counts, coordinate fractions) into one `Config` struct

## Native menu-bar app

### Prerequisites (from Phase 1)
- [ ] Capture live AX dumps during a real re-authenticate session; record in [phase1.md](phase1.md) §3 (the one Phase 1 item still open)

### Xcode project bootstrap
- [ ] Create macOS App target (Swift, AppKit or AppKit + SwiftUI Settings)
- [ ] Set stable bundle ID; deployment target macOS 14
- [ ] Disable App Sandbox; enable Hardened Runtime
- [ ] Add `LSUIElement` menu-bar agent lifecycle (no Dock icon)
- [ ] Wire Debug/Release schemes; `.gitignore` for `xcuserdata`, build products

### Core modules
- [ ] `NetskopeAppResolver` — locate running `com.netskope.client.Netskope-Client` / "Netskope Client"
- [ ] `AXTree` — DFS walker; safe string coercion; find text fields & buttons by predicate
- [ ] `PageDetector` — Step 1 (Continue) vs Step 2 (Next / Sign in)
- [ ] `KeystrokePoster` — `Cmd+A`, type string, Return; posted to the Netskope PID
- [ ] `ContinuePress` — poll `AXEnabled`, `AXPress`, coordinate-fallback flag
- [ ] `LoginStateMachine` — FR-8 states; single-flight; 30s cooldown; 20s Microsoft wait
- [ ] `WindowWatcher` — subscribe to Netskope window appear/focus; debounce into the state machine
- [ ] `EmailStore` — `UserDefaults` read/write for email1 / email2
- [ ] `AccessibilityGate` — trust check, Settings deep link, status for UI
- [ ] `Logger` — rotating file + OSLog; redact options

### Menu-bar interface
- [ ] Status item with state-aware title/image
- [ ] Menu: Run Sequence, Step 1, Step 2, Settings…, Open Logs, Launch at Login toggle, Quit
- [ ] Settings: email1, email2, enable auto-run, enable hotkeys, reveal log folder
- [ ] Optional hotkeys ⌘⌥1 / ⌘⌥2 (Step 1 / Step 2 manual triggers)

### Permissions & login item
- [ ] Prompt / guide Accessibility on first need
- [ ] Block automation when untrusted
- [ ] `SMAppService` launch-at-login toggle (default off)

### Behavior validation
- [ ] Capture live AX dumps; update [phase1.md](phase1.md) §3
- [ ] Run S01–S03, S10–S13, S20–S22, S30–S35, S40–S43 from [phase1.md](phase1.md) §6
- [ ] Compare behavior against the CLI script on the same re-auth prompt (side-by-side once)
- [ ] Confirm Enter is **not** used for Step 1 and **is** used for Step 2

### Packaging prep (not full rollout)
- [ ] Archive signed Debug/Release with Developer ID (when a cert is available)
- [ ] Smoke notarization on a release candidate
- [ ] Draft IT allowlist blurb (bundle ID, team ID, purpose)

### Exit criteria (Phase 2 → Phase 3)
- [ ] Happy path works standalone — native app only, no third-party automation tools
- [ ] Phase 1 acceptance scenarios S13 / S21 / S31–S34 / S40–S42 pass
- [ ] No password/MFA handling introduced
- [ ] README for local run + Accessibility setup

## Phase 3+ (future, not started)
- [ ] Polish UI, icons, onboarding screenshots
- [ ] Coordinated Jamf pkg + EDR allowlist
- [ ] Telemetry opt-in for failure rates (no email content)
- [ ] Handle Netskope UI regressions / multi-field forms

## Permanent fix (preferred over any automation)
- [ ] Ask IT to enable IdP/seamless enrollment, or extend the Netskope tenant's re-authentication period — removes the email prompt entirely
