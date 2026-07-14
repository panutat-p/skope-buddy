# ADR-001 — Native macOS Architecture for Netskope Autofill

**Status:** Accepted  
**Date:** 2026-07-14  
**Context:** Replace Hammerspoon Lua automation with a native app (`skope-buddy`) while preserving proven behavior.

## Context

The existing Hammerspoon script:

- Watches Netskope Client windows (including non-standard roles)
- Fills `@kkpfg.com` then presses Continue via AX
- Detects the Microsoft page via AX text/buttons
- Fills `@phatrasec.com` and submits with Enter
- Uses process-targeted keystrokes and a 30s cooldown

Constraints from notes and environment:

- Managed Mac (Jamf / Cortex XDR / Admin By Request) may scrutinize unsigned input injectors
- Must be non-sandboxed for Accessibility automation
- MFA stays manual
- No passwords stored

## Decisions

### D1 — Product shape: menu-bar agent (LSUIElement)

**Decision:** Ship as a menu-bar–only app (agent), not a Dock document app.

**Why:** Matches Netskope’s own agent UX; autofill is background infrastructure; settings/logs fit a status-item menu.

### D2 — Language and frameworks: Swift + AppKit + ApplicationServices

**Decision:** Implement in Swift using:

| Concern | API |
|---------|-----|
| Menu bar / settings | AppKit (`NSStatusItem`, `NSWindow` or Settings scene) |
| Accessibility tree | `ApplicationServices` (`AXUIElement`) |
| Targeted keystrokes | `CoreGraphics` (`CGEvent` posted to Netskope PID) |
| App lifecycle watch | `NSWorkspace` + AX observer / polling hybrid |
| Launch at login | `SMAppService` (Login Item) |
| Local settings | `UserDefaults` for emails and preferences (see D6) |

**Why:** Direct mapping from Hammerspoon’s `hs.axuielement` + `hs.eventtap`; smallest dependency surface; no Hammerspoon runtime.

**Alternatives rejected:** Keep Hammerspoon (works but not the project goal); SwiftUI-only without AppKit status item patterns; Electron/Python (heavier, harder to notarize cleanly for AX).

### D3 — State machine as first-class module

**Decision:** Encode FR-8 states explicitly; all timers owned by the state machine (avoid GC/lifetime bugs that bit Hammerspoon v6).

```
Idle → WindowDetected → FirstIdentityFilled → ContinueActivated
  → WaitingMicrosoft → SecondIdentityFilled → FormSubmitted → Cooldown → Idle
                                         ↘ Recovery → Idle
```

Single-flight: one sequence at a time.

### D4 — AX for structure; keyboard for webview text

**Decision:** Per accessibility findings — never rely on `AXValue` writes for email entry; use targeted keystrokes; use `AXPress` for Continue when enabled.

### D5 — Window observation strategy

**Decision:** Primary: observe windows for `com.netskope.client.Netskope-Client` via Accessibility / workspace notifications; treat created/visible/focused as triggers with cooldown. Secondary: manual menu/hotkey.

Do not depend on screen coordinates for the happy path.

### D6 — Email storage

**Decision:** Store both emails in **UserDefaults** (app suite), not Keychain.

**Why:**

- Values are identities, not secrets (same addresses appear in clear UI)
- Simpler backup/restore and Settings binding
- Keychain adds friction without meaningful threat reduction for email strings

**Mitigations:** Restrict log redaction options; do not sync via iCloud KVS unless explicitly added later; file permissions follow standard app container / preferences.

**Rejected:** Hard-coded emails in binary; Keychain mandatory for emails; storing passwords.

### D7 — Permissions and trust UX

**Decision:** First-class Accessibility onboarding; hard-stop automation until trusted. No attempt to bypass TCC.

### D8 — Distribution: Developer ID + notarization, non-sandboxed

**Decision:** Outside Mac App Store; Developer ID Application signing; notarize; staple. Entitlements: App Sandbox **off**; no entitlement replaces user-granted Accessibility.

**Why:** Sandbox blocks the required AX control of another app. Notes warn unsigned binaries lose Accessibility trust on rebuild and may be flagged by EDR — signing+notarization is mandatory for managed Macs.

### D9 — Hotkeys and parity

**Decision:** Preserve optional `⌘⌥1` / `⌘⌥2` as manual Step 1 / Step 2; primary UX is menu + auto trigger.

### D10 — Logging

**Decision:** Rotating local log file + menu “Open Logs”; levels for state transitions; never log raw passwords (none handled) and optionally redact email local-parts.

## Consequences

- Phase 2 implements AX walker, event poster, state machine, status item — not a Lua port.
- QA must re-validate after Netskope Client updates (webview AX can change).
- IT communication may still be needed for allowlisting the notarized bundle ID on EDR.
- Permanent fix remains IdP/seamless enrollment; this app is a user-side mitigator.

## References

- `docs/phase1/01-functional-requirements.md`
- `docs/phase1/02-accessibility-findings.md`
- `docs/phase1/04-permission-distribution-plan.md`
- `hammer_spoon/netskope-autofill.lua`
- `hammer_spoon/netskope-autofill-notes.md`
