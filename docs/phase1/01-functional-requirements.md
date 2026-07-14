# Functional Requirements — Skope Buddy

**Phase:** 1  
**Source of truth for behavior:** `hammer_spoon/netskope-autofill.lua` (v7) and `hammer_spoon/netskope-autofill-notes.md`  
**Status:** Approved for Phase 2 implementation planning

## 1. Purpose

Skope Buddy is a native macOS menu-bar app that replaces the Hammerspoon Netskope re-authentication autofill script. It fills two email identities in sequence when the Netskope Client shows the Private Access re-authenticate window, then stops so MFA remains manual.

## 2. Confirmed environment

| Item | Value |
|------|--------|
| Target process name | `Netskope Client` |
| Bundle identifier | `com.netskope.client.Netskope-Client` |
| Observed client version | `138.0.2.2681` |
| Client `LSMinimumSystemVersion` | `10.11` (vendor claim) |
| Client UI style | Agent / menu-bar (`LSUIElement = 1`) |
| Login window title (observed) | `Re-authenticate Private Access` |
| Host macOS for validation | macOS 15.7.1 (Sequoia) |
| Skope Buddy supported OS | **macOS 14 Sonoma and later** (Apple Silicon + Intel) |

Rationale for OS floor: Accessibility, Launch at Login, and notarized Developer ID distribution are reliable on 14+; older Netskope client support does not require Skope Buddy to target 10.11.

## 3. Actors and assets

- **User:** configures two email addresses, grants Accessibility, triggers or allows autofill.
- **Skope Buddy:** menu-bar agent; watches Netskope; drives the two-step fill.
- **Netskope Client:** owns the re-authenticate window (embedded webviews for Netskope + Microsoft IdP).
- **Out of scope actors:** password managers, MFA apps, IT MDM policies (except as constraints).

## 4. Functional requirements

### FR-1 Detect re-authenticate window

- Watch for windows belonging to `com.netskope.client.Netskope-Client` / process name `Netskope Client`.
- Must include non-standard / panel-style windows (Hammerspoon required `allowRoles = "*"`; Netskope is `LSUIElement`).
- Prefer title match containing `Re-authenticate` when available; do not rely on title alone if AX content confirms a sign-in form.
- Do not activate autofill for unrelated Netskope UI (e.g. preference panes without email fields).

### FR-2 Identify Step 1 (Netskope identity page)

- Page is the first embedded form requiring a corporate email.
- Reliable signals (any sufficient combination):
  - `AXTextField` / `AXTextArea` present
  - `AXButton` whose title/description matches `/continue/i`
  - Absence of Microsoft markers (`Next`, `Sign in` heading) until after Continue

### FR-3 Fill first identity and continue

- Email 1 default pattern: `<user>@kkpfg.com` (user-configurable).
- Focus the email field via Accessibility (`AXFocused = true`).
- Clear existing content (`Cmd+A`) and type the email with **process-targeted keystrokes** (not system-wide event taps that can hit other apps).
- Wait until the Continue button reports `AXEnabled == true` (poll ≤ ~0.4s, max ~8 attempts / ~3.2s), then `AXPress`.
- If AX button is missing or never enables: optional coordinate fallback (window-relative fractions from Hammerspoon: field ~0.50×0.68, button ~0.50×0.78) — log clearly when used.
- **Do not** submit Step 1 with Enter; the Netskope webview does not treat Enter as Continue.

### FR-4 Detect Step 2 (Microsoft / IdP page)

- After Continue, poll the AX tree (~0.3s) for Microsoft page markers:
  - `AXButton` title/description matching `/next/i`, or
  - `AXStaticText` / `AXHeading` value/title matching `/sign in/i`
- Timeout: **20 seconds**, then either run Step 2 best-effort or enter recovery (see FR-8). Prefer detecting the page over a fixed sleep.

### FR-5 Fill second identity and submit

- Email 2 default pattern: `<user>@phatrasec.com` (user-configurable).
- Same focus + process-targeted typing as Step 1.
- Submit with **Return/Enter** targeted at the Netskope process (validated behavior on the Microsoft page).
- Coordinate fallback for field if needed: ~0.50×0.24 of window.

### FR-6 Input targeting and focus safety

- Keystrokes and synthetic keys must be delivered to the Netskope Client process only.
- Focusing the Netskope window before typing is required.
- Autofill must not type into an unrelated foreground app if Netskope loses focus mid-sequence; abort or re-acquire Netskope focus, then continue or recover.

### FR-7 Cooldown and de-duplication

- After a sequence starts, suppress automatic re-triggers for **30 seconds** (Hammerspoon `lastFired` behavior) to absorb multiple window created/visible/focused events.
- Manual triggers may bypass cooldown with an explicit user action (menu / hotkey), but must still be single-flight (no overlapping sequences).

### FR-8 State machine, retries, recovery

Implement the proposed flow:

1. Idle  
2. Netskope window detected  
3. First identity filled  
4. Continue activated  
5. Waiting for Microsoft sign-in page  
6. Second identity filled  
7. Form submitted  
8. Cooldown or recovery  

Bounded behavior:

| Condition | Behavior |
|-----------|----------|
| No Netskope window | Stay Idle; log skip |
| No email field (Step 1/2) | Coordinate fallback once; if still failing → Recovery |
| Continue never enables | After max polls → coordinate button click once; else Recovery |
| Microsoft page timeout (20s) | Best-effort Step 2 **or** Recovery with user-visible notice |
| Mid-sequence focus loss | Re-focus Netskope once; on failure → Recovery |
| Overlapping trigger | Ignore while sequence active or within cooldown |

**Recovery:** stop timers, return to Idle (or Cooldown), surface menu-bar status / notification, leave Manual Trigger available. Never loop unbounded.

### FR-9 Manual controls

- Menu items (minimum): Run autofill sequence, Run Step 1 only, Run Step 2 only, Open Settings, Open Logs, Quit.
- Optional hotkeys (parity with Hammerspoon): `⌘⌥1` Step 1, `⌘⌥2` Step 2; document and make remappable or disableable in Settings.

### FR-10 Settings and secrets policy

- Persist two email strings locally (see ADR / storage decision).
- **Never** capture, log, or store passwords, MFA codes, cookies, or auth tokens.
- Logs may include window titles, AX roles/titles used for matching, state transitions, and timings — not keystroke contents beyond “typed email 1/2” (optionally redact local-part in verbose logs).

### FR-11 Accessibility permission UX

- On launch, check trusted Accessibility status.
- If missing: first-run / blocked state with clear copy, button to open System Settings → Privacy & Security → Accessibility, and how to re-check.
- While untrusted: do not send keystrokes; show persistent menu-bar indication.

### FR-12 Launch at login

- User-toggleable “Open at Login” via SMAppService / Login Items API (macOS 13+; we support 14+).
- Default: off until the user opts in (or on after successful first run — product choice in ADR: **default off**).

### FR-13 Observability

- In-app or file log of state transitions and failures (sufficient to debug without Console.app only).
- Menu-bar icon reflects: Idle / Needs permission / Running / Recovery / Cooldown (exact artwork deferred to UI phase).

## 5. Non-functional requirements

| ID | Requirement |
|----|-------------|
| NFR-1 | Replace Hammerspoon; no runtime dependency on Hammerspoon Lua. |
| NFR-2 | Non-sandboxed app (Accessibility + targeted input). |
| NFR-3 | Distributed as Developer ID signed + notarized (see distribution plan). |
| NFR-4 | Sequence completes under ~5s after Microsoft page appears in the happy path; detection polls must not freeze the UI. |
| NFR-5 | Fail closed on secrets: no password fields read or written. |

## 6. Explicit non-goals (Phase 1+)

- Automatic password entry or MFA approval.
- Sandboxed Mac App Store distribution.
- Changing Netskope tenant / IdP policy (IT seamless enrollment remains the preferred permanent fix).
- Supporting Netskope Endpoint DLP or Remove Netskope Client apps as automation targets.
