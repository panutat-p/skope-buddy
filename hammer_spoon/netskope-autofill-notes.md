# Netskope ZTNA Auto-Login — Project Notes

## Goal

Automate the Netskope Client re-authentication prompt on macOS, which requires two emails in sequence:

1. Netskope page: `<user email>@kkpfg.com` → **Continue**
2. Microsoft (Kiatnakin Phatra) page: `<user email>@phatrasec.com` → **Next**

MFA approval on the auth app remains manual (by design).

## Solution

A Hammerspoon script (`netskope-autofill.lua`, currently v7) placed in `~/.hammerspoon/init.lua`.

### How it works

1. A window filter watches for any window from the **Netskope Client** app (including non-standard panels — the login window title is `Re-authenticate Private Access`).
2. **Step 1**: finds the email field via the macOS accessibility (AX) API, focuses it, types email 1 with real keystrokes, waits for the Continue button to enable (polling `AXEnabled`), then presses it via `AXPress`.
3. **Page detection**: polls the AX tree every 0.3s until the Microsoft page appears (detected by a "Next" button or "Sign in" text). No static delay; 20s timeout fallback.
4. **Step 2**: focuses the field, types email 2, submits with **Enter** (the Microsoft page accepts it; the Netskope page does not).
5. A 30s cooldown prevents duplicate runs from multiple window events.

### Fallbacks

- Hotkeys: `⌘⌥1` = step 1, `⌘⌥2` = step 2 (manual trigger).
- If AX can't find the field/button, it falls back to coordinate clicks (fractions of window size, measured from screenshots).

## Key lessons learned (debugging history)

| Problem | Root cause | Fix |
|---|---|---|
| Auto-trigger never fired | `hs.window.filter` ignores non-standard windows by default | `setAppFilter(APP_NAME, {allowRoles = "*"})` |
| Enter didn't click Continue; both emails landed in one field | Netskope page is a webview; Enter doesn't submit | Click/AXPress the Continue button instead |
| Continue stayed grayed out after filling the field | Setting `AXValue` directly doesn't fire the webview's JS input events | AX-focus the field but type with real keystrokes; poll `AXEnabled` before pressing |
| Step 2 clicked the wrong spot | Microsoft page has a different layout and a "Next" button | Per-step config (button label, coordinates); later switched step 2 to Enter |
| Keystrokes typed into other apps (e.g. chat) | `hs.eventtap.keyStrokes` is system-wide | Pass the app object: `keyStrokes(text, app)` — events go directly to Netskope |
| Step 2 silently never ran | Un-referenced `hs.timer.doAfter` timers get garbage-collected | Keep all timers in a global table |
| Crash: "attempt to index a number value" | `AXValue` can return a number; `:find()` on it fails | Wrap in `tostring()` |

## Configuration knobs (top of script)

- `APP_NAME` — must match the process name exactly (`Netskope Client`).
- `STEP1` / `STEP2` — email, button pattern, fallback coordinates per step.
- Poll interval (0.3s) and 20s timeout in `waitThenRunStep2`.

## Testing procedure

1. Hammerspoon menu → Reload Config; check Console for `v7 loaded`.
2. Test typing: `⌘⌥1` in TextEdit (verifies Accessibility permission).
3. Trigger re-authenticate in Netskope; watch Console for `step1: ...`, `Microsoft page detected after X.Xs`, `step2: ...`.

## Standalone Swift app (considered, not built)

Feasible (~200 lines: `AXUIElement` + `CGEvent` + LaunchAgent), but not recommended on this managed Mac:

- Unsigned binary → Accessibility permission may reset on every rebuild.
- Jamf / Cortex XDR / Admin By Request may flag an unsigned binary injecting input into a security client; Hammerspoon is a known signed app.
- Recompile vs. edit-and-reload for every tweak.

## Recommended permanent fix

Ask IT to enable **IdP/seamless enrollment** or extend the re-authentication period in the Netskope tenant — this removes the email prompt entirely, no automation needed.
