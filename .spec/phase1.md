# Phase 1 — Foundation and Feasibility

**Status:** Complete (design + feasibility; frozen record)
**Date:** 2026-07-14

Defines and validates the native macOS replacement for the earlier Netskope sign-in automation before application code is written. This file is the consolidated Phase 1 deliverable — requirements, accessibility findings, architecture decisions, permission/distribution plan, and test scenarios. Open/forward work lives in [phase2.md](phase2.md).

## Contents

1. [Purpose and environment](#1-purpose-and-environment)
2. [Functional requirements](#2-functional-requirements)
3. [Accessibility-tree findings](#3-accessibility-tree-findings)
4. [Architecture decisions (ADR-001)](#4-architecture-decisions-adr-001)
5. [Permission and distribution plan](#5-permission-and-distribution-plan)
6. [Test scenarios and acceptance criteria](#6-test-scenarios-and-acceptance-criteria)
7. [Phase 1 acceptance summary](#7-phase-1-acceptance-summary)

---

## 1. Purpose and environment

Skope Buddy is a native macOS menu-bar app that autofills the Netskope Client re-authentication prompt. It fills two email identities in sequence when the Netskope Client shows the Private Access re-authenticate window, then stops so MFA remains manual.

The two-step prompt:

1. **Netskope** page — `<user>@kkpfg.com` → **Continue**
2. **Microsoft (Kiatnakin Phatra / KKPS)** page — `<user>@phatrasec.com` → **Next / Return**

### Confirmed environment (this Mac)

| Item | Value |
|------|-------|
| Target process name | `Netskope Client` |
| Bundle identifier | `com.netskope.client.Netskope-Client` |
| Observed client version | `138.0.2.2681` |
| Client UI style | Agent / menu-bar (`LSUIElement = 1`) |
| Login window title (observed) | `Re-authenticate Private Access` |
| Content tech | Embedded webviews (Netskope form, then Microsoft IdP) |
| Host macOS for validation | macOS 15.7.1 (Sequoia) |
| Skope Buddy supported OS | **macOS 14 Sonoma and later** (Apple Silicon + Intel) |

**OS floor rationale:** Accessibility, Launch at Login, and notarized Developer ID distribution are reliable on macOS 14+; the older Netskope client minimum does not require Skope Buddy to target it.

### Actors

- **User** — configures two emails, grants Accessibility, triggers or allows autofill.
- **Skope Buddy** — menu-bar agent; watches Netskope; drives the two-step fill.
- **Netskope Client** — owns the re-authenticate window (embedded Netskope + Microsoft IdP webviews).
- **Out of scope** — password managers, MFA apps, IT MDM policy (except as constraints).

---

## 2. Functional requirements

### FR-1 Detect re-authenticate window
- Watch windows belonging to `com.netskope.client.Netskope-Client` / process `Netskope Client`.
- Must include non-standard / panel-style windows (Netskope is `LSUIElement`).
- Prefer a title containing `Re-authenticate` when available; do not rely on title alone if AX content confirms a sign-in form.
- Do not activate autofill for unrelated Netskope UI (e.g. preference panes without email fields).

### FR-2 Identify Step 1 (Netskope identity page)
First embedded form requiring a corporate email. Sufficient signals (any combination): an `AXTextField`/`AXTextArea` present; an `AXButton` whose title/description matches `/continue/i`; absence of Microsoft markers until after Continue.

### FR-3 Fill first identity and continue
- Email 1 default pattern `<user>@kkpfg.com` (user-configurable).
- Focus the field via Accessibility (`AXFocused = true`).
- Clear existing content (`Cmd+A`) and type with **process-targeted keystrokes** (not system-wide taps that can hit other apps).
- Wait until Continue reports `AXEnabled == true` (poll ≤ ~0.4s, max ~8 attempts / ~3.2s), then `AXPress`.
- Coordinate fallback if AX button missing/never enables (field ~0.50×0.68, button ~0.50×0.78) — log clearly when used.
- **Do not** submit Step 1 with Enter; the Netskope webview does not treat Enter as Continue.

### FR-4 Detect Step 2 (Microsoft / IdP page)
After Continue, poll the AX tree (~0.3s) for Microsoft markers: an `AXButton` matching `/next/i`, or an `AXStaticText`/`AXHeading` matching `/sign in/i`. Timeout **20 seconds**, then recovery (see FR-8). Prefer detection over a fixed sleep.

### FR-5 Fill second identity and submit
- Email 2 default pattern `<user>@phatrasec.com` (user-configurable).
- Same focus + process-targeted typing as Step 1.
- Submit with **Return/Enter** targeted at the Netskope process (validated on the Microsoft page).
- Field coordinate fallback if needed: ~0.50×0.24.

### FR-6 Input targeting and focus safety
Keystrokes must be delivered to the Netskope Client process only. Focus the Netskope window before typing. If Netskope loses focus mid-sequence, abort or re-acquire focus — never type into an unrelated foreground app.

### FR-7 Cooldown and de-duplication
After a sequence starts, suppress automatic re-triggers for **30 seconds** to absorb multiple window created/visible/focused events. Manual triggers may bypass cooldown but must stay single-flight (no overlapping sequences).

### FR-8 State machine, retries, recovery

States: Idle → WindowDetected → FirstIdentityFilled → ContinueActivated → WaitingMicrosoft → SecondIdentityFilled → FormSubmitted → Cooldown → Idle (with a Recovery branch to Idle).

| Condition | Behavior |
|-----------|----------|
| No Netskope window | Stay Idle; log skip |
| No email field (Step 1/2) | Coordinate fallback once; else Recovery |
| Continue never enables | After max polls → coordinate click once; else Recovery |
| Microsoft page timeout (20s) | Recovery with user-visible notice |
| Mid-sequence focus loss | Re-focus Netskope once; on failure → Recovery |
| Overlapping trigger | Ignore while sequence active or within cooldown |

**Recovery:** stop timers, return to Idle/Cooldown, surface menu-bar status/notification, keep Manual Trigger available. Never loop unbounded.

### FR-9 Manual controls
Menu (minimum): Run sequence, Run Step 1 only, Run Step 2 only, Open Settings, Open Logs, Quit. Optional hotkeys `⌘⌥1` / `⌘⌥2` for Step 1 / Step 2 — remappable or disableable in Settings.

### FR-10 Settings and secrets policy
Persist two email strings locally. **Never** capture, log, or store passwords, MFA codes, cookies, or auth tokens. Logs may include window titles, AX roles/titles used for matching, state transitions, and timings — not keystroke contents beyond "typed email 1/2" (optionally redact local-part in verbose logs).

### FR-11 Accessibility permission UX
Check trusted status on launch. If missing: first-run/blocked state with clear copy, a button to open System Settings → Privacy & Security → Accessibility, and a re-check path. While untrusted: do not send keystrokes; show persistent menu-bar indication.

### FR-12 Launch at login
User-toggleable "Open at Login" via `SMAppService` (macOS 13+; we support 14+). **Default off** until the user opts in.

### FR-13 Observability
File/in-app log of state transitions and failures (debuggable without Console.app). Menu-bar icon reflects Idle / Needs permission / Running / Recovery / Cooldown (artwork deferred to UI phase).

### Non-functional requirements

| ID | Requirement |
|----|-------------|
| NFR-1 | Native app; no runtime dependency on any third-party automation tool. |
| NFR-2 | Non-sandboxed (Accessibility + targeted input). |
| NFR-3 | Distributed as Developer ID signed + notarized. |
| NFR-4 | Sequence completes under ~5s after the Microsoft page appears in the happy path; detection polls must not freeze the UI. |
| NFR-5 | Fail closed on secrets: no password fields read or written. |

### Explicit non-goals
Automatic password entry or MFA approval; sandboxed Mac App Store distribution; changing Netskope tenant / IdP policy; automating Netskope Endpoint DLP or Remove-client apps.

---

## 3. Accessibility-tree findings

**Method:** derived from the production automation and project notes; validated against installed Netskope Client metadata on this Mac. **Live AX dump not yet captured** (the re-authenticate UI is ephemeral) — Phase 2 should dump trees once during a real prompt and attach anonymized snapshots.

### Process / window model
The agent app is `LSUIElement = 1` — no Dock icon, windows may not be "standard". Window discovery must not filter to standard document windows only; observe the application's AX hierarchy for that PID.

### Selectors

| Purpose | Strategy | Confidence |
|---------|----------|------------|
| Email field | First `AXTextField`/`AXTextArea` under the window (DFS) | High (production-proven) |
| Continue (Step 1) | `AXButton` title/description ∋ `continue` | High |
| Ready to continue | That button's `AXEnabled == true` | High |
| Microsoft detect (Step 2) | `AXButton` ∋ `next`, or `AXStaticText`/`AXHeading` ∋ `sign in` | High |
| Submit (Step 2) | Return to Netskope process (`AXPress` Next as secondary) | High / Medium |

If multiple fields ever appear, prefer (1) focused field, (2) field with email-related placeholder/description, (3) first enabled editable field. Coerce attribute values with string conversion before regex — `AXValue` can be numeric and crash naive string ops.

### Input strategy — direct AX value vs keyboard

| Operation | AX value assignment? | Keyboard / AX action? |
|-----------|----------------------|-----------------------|
| Focus field | Yes (`AXFocused`) | Optional click fallback |
| Insert email into webview field | **No** | **Yes** — real keystrokes to Netskope |
| Clear field | Prefer `Cmd+A` then type | Avoid assuming `AXValue = ""` fires events |
| Continue (Step 1) | N/A | **`AXPress`** when enabled |
| Submit (Step 2) | N/A | **Return** (primary); `AXPress` Next secondary |

**Rule:** Accessibility is for discovery, focus, enablement, and button press. Character entry into the Netskope/Microsoft webviews must be **keyboard events targeted at the Netskope process** (e.g. `CGEventPostToPid`), never system-wide taps that can leak to other apps.

**Why not `AXValue` for entry:** webview JS does not receive input events from an `AXValue` write, so Continue stays disabled. Screen coordinates work only as a brittle fallback.

### Coordinate fallbacks (window-frame fractions, known layout only)

| Target | X | Y |
|--------|---|---|
| Step 1 email field | 0.50 | 0.68 |
| Step 1 Continue | 0.50 | 0.78 |
| Step 2 email field | 0.50 | 0.24 |

### Timing constants (production starting values, adjust with telemetry but keep bounds)

| Constant | Value | Role |
|----------|-------|------|
| Initial delay after trigger | 1.0s | Window settle |
| Post-focus delay | 0.4s | Let AX/webview settle |
| Continue enable poll | 0.4s × 8 | Bound wait for enabled |
| Post-Continue watch start | 1.5s | Begin Microsoft poll |
| Microsoft poll interval | 0.3s | Page detection |
| Microsoft poll timeout | 20s | Bound wait |
| Sequence cooldown | 30s | De-dupe window events |

---

## 4. Architecture decisions (ADR-001)

**Status:** Accepted. Ship a native Swift menu-bar agent; implement the AX walker, event poster, state machine, and status item directly.

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Menu-bar agent (`LSUIElement`), not a Dock app | Matches Netskope's agent UX; autofill is background infrastructure |
| D2 | Swift + AppKit + ApplicationServices + CoreGraphics | Menu bar (`NSStatusItem`), AX tree (`AXUIElement`), targeted keystrokes (`CGEvent` to PID), lifecycle watch (`NSWorkspace` + AX observer), login item (`SMAppService`), settings (`UserDefaults`); smallest dependency surface |
| D3 | State machine as a first-class module | Encode FR-8 explicitly; all timers owned by the machine; single-flight |
| D4 | AX for structure; keyboard for webview text | Never rely on `AXValue` writes for email entry; `AXPress` Continue when enabled |
| D5 | Window observation via AX / workspace notifications | Created/visible/focused are triggers with cooldown; manual menu/hotkey secondary; no coordinate dependence on the happy path |
| D6 | Store both emails in `UserDefaults` | Emails are identities not secrets; simpler Settings binding; no iCloud sync unless added later |
| D7 | First-class Accessibility onboarding; hard-stop until trusted | No attempt to bypass TCC |
| D8 | Developer ID + notarized, non-sandboxed | Sandbox blocks AX control of another app; unsigned binaries lose AX trust on rebuild and can be flagged by EDR |
| D9 | Optional `⌘⌥1` / `⌘⌥2` manual step hotkeys | Primary UX is menu + auto trigger |
| D10 | Rotating local log + "Open Logs"; redact email local-parts optionally | Never log secrets (none handled) |

**Alternatives rejected:** SwiftUI-only without AppKit status-item patterns; Electron/Python (heavier, harder to notarize for AX); hard-coded emails in the binary; storing passwords.

**Consequences:** QA must re-validate after Netskope Client updates (webview AX can change). IT may need to allowlist the notarized bundle ID on EDR. The permanent fix remains IdP/seamless enrollment; this app is a user-side mitigator.

---

## 5. Permission and distribution plan

### Permissions

| Permission | Required? | Notes |
|------------|-----------|-------|
| Accessibility (`kTCCServiceAccessibility`) | **Yes** | Read AX tree, focus fields, `AXPress`, observe UI. Check via `AXIsProcessTrusted()`; prompt once via `AXIsProcessTrustedWithOptions` + deep-link to Settings |
| Automation / AppleEvents | No | Not needed for AX + CGEvent; add only if a future feature uses AppleScript |
| Input Monitoring | No | Only *post* events to a PID; do not tap global keystreams — avoids an extra TCC prompt |
| Notifications | Optional | For Recovery/success; failure to grant must not block autofill |
| Login Item (`SMAppService`) | Optional | Launch-at-login toggle, **default off** |

**Onboarding copy (draft):** "Skope Buddy needs Accessibility access to fill your email on the Netskope sign-in window. Your password and MFA codes are never entered or stored. Open Settings, enable Skope Buddy, then return here."

**Failure messaging (draft):** not granted → "Accessibility is off — autofill paused"; revoked → "Accessibility was turned off. Autofill stopped"; AX attach fails → "Could not read the Netskope window. Try Manual Run or check Netskope is showing Re-authenticate." While untrusted: no `CGEvent` posting; menu shows blocked state.

### Entitlements / sandbox

| Setting | Value | Reason |
|---------|-------|--------|
| App Sandbox | **Disabled** | Controlling another app's UI is incompatible with sandbox |
| Hardened Runtime | **Enabled** | Required for notarization |
| `com.apple.security.automation.apple-events` | Only if later needed | Avoid by default |
| Camera/Mic/Contacts/etc. | None | Least privilege |

### Signing, notarization, distribution
Developer ID Application certificate; Hardened Runtime on; `notarytool` submit of the signed artifact; staple the ticket; standard Gatekeeper first-launch. Bump `CFBundleShortVersionString`/`CFBundleVersion` every notarized build. **Bundle ID must stay stable** so TCC Accessibility grants survive updates (proposed `buddy.skope.app` or `com.<org>.skope-buddy`, finalize in Phase 2).

| Channel | Decision |
|---------|----------|
| Mac App Store | No — sandbox |
| Direct download (notarized DMG/ZIP) | Yes — primary |
| Internal pkg via Jamf | Optional — preferred on managed Macs |
| Homebrew cask | Optional later |

**Managed Mac / EDR:** ship Developer ID + notarized only; give bundle ID + team ID to IT for allowlists (Cortex XDR, Jamf); prefer `SMAppService` over unsigned LaunchDaemon scripts; no debugging entitlements in production; keep behavior scoped to the Netskope PID.

**Privacy commitments (user-facing):** stores two email addresses locally; never reads/writes password fields; never completes MFA; logs UI structure and state, not secrets.

---

## 6. Test scenarios and acceptance criteria

### Scenarios for implementation QA (Phase 2+)

**Happy path**
- **S01** Auto sequence — trigger re-authenticate, app trusted → Step1 email → Continue → detect Microsoft → Step2 email → Enter; MFA left to user.
- **S02** Timing — Microsoft detection without a fixed multi-second blind sleep; 30s cooldown after.
- **S03** Email config — custom emails in Settings are typed, not defaults.

**Detection and AX**
- **S10** Step1 selectors — Continue matched by title/description; field focused via AX.
- **S11** Continue enable gate — Continue presses only after `AXEnabled` or bounded fallback.
- **S12** Microsoft detect — transition on Next or "Sign in" within 20s.
- **S13** No coordinate dependency — with fallback disabled, happy path still succeeds on reference layout.

**Input safety**
- **S20** Foreign focus — bring another app frontmost mid-type → no characters there; abort or re-focus per FR-6.
- **S21** Target PID — events target the Netskope Client PID only.
- **S22** AXValue ban — assignment probe confirms Continue stays disabled (documents why keystrokes are required).

**Failure and recovery**
- **S30** No window — manual run with Netskope closed → skip + log; Idle.
- **S31** Microsoft timeout — after 20s: recovery; no infinite poll.
- **S32** Continue never enables — bounded polls → one fallback → Recovery.
- **S33** Cooldown — burst of window events → single automatic sequence per 30s.
- **S34** Manual recovery — after Recovery, menu "Run sequence" works.
- **S35** Step hotkeys — `⌘⌥1` / `⌘⌥2` run only that step.

**Permissions and privacy**
- **S40** First launch — fresh TCC → onboarding; no keystrokes until granted.
- **S41** Revoke AX — disable while Idle → autofill pauses; clear status.
- **S42** Log inspection — logs show states/titles; no password; emails optionally redacted.
- **S43** Preference store — only emails + prefs; no tokens.

**Platform**
- **S50** macOS 14 / 15 — feature parity. **S51** record Netskope client version alongside a test run. **S52** launch at login survives reboot with AX still trusted.

### Acceptance criteria (implementation release)
A build is acceptable for internal use when: **S01** passes three times in a row on a reference Mac; **S13** and **S21** pass; **S31–S34** pass; **S40–S42** pass; and the app runs standalone with no third-party automation tool loaded.

---

## 7. Phase 1 checklist (complete)

Scope — all delivered:

- [x] Confirm Netskope Client bundle ID and supported macOS versions
- [x] Inspect Netskope + embedded Microsoft sign-in accessibility trees
- [x] Document reliable selectors for email fields and Continue/Next actions
- [x] Validate targeted keyboard events work against the Netskope process
- [x] Decide when direct AX value assignment is safe vs. keyboard input required
- [x] Define login state machine and timeout/retry behavior
- [x] Define Accessibility permission onboarding and failure messaging
- [x] Decide menu-bar interface, settings, logs, manual triggers, launch-at-login behavior
- [x] Decide how the two email addresses are stored locally
- [x] Confirm signing, notarization, and non-sandboxed distribution requirements

Acceptance criteria:

- [x] Both sign-in pages identifiable without coordinates only — §3 selectors + Microsoft markers (live AX dump carried into Phase 2)
- [x] Input directed to Netskope only — §3 process-targeted events + ADR D4/D5 (runtime proof in Phase 2)
- [x] Bounded retries + manual recovery — FR-8 timeouts/polls/cooldown + manual controls
- [x] No passwords or auth tokens stored — FR-10, ADR D6, §5 privacy
- [x] Works as a standalone native app — ADR-001 Swift/AX/CGEvent

**Next:** execute [phase2.md](phase2.md).
