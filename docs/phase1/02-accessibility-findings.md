# Accessibility-Tree Findings

**Phase:** 1  
**Method:** Reverse-engineered from production Hammerspoon script `netskope-autofill.lua` v7 and project notes; validated against installed Netskope Client metadata on this Mac.  
**Live AX dump:** Not captured in this phase (re-authenticate UI is ephemeral). Phase 2 should dump trees once during a real prompt and attach anonymized snapshots here.

## 1. Process and window model

| Attribute | Finding |
|-----------|---------|
| App name | `Netskope Client` |
| Bundle ID | `com.netskope.client.Netskope-Client` |
| Agent app | `LSUIElement = 1` — no Dock icon; windows may not be “standard” |
| Login window title | `Re-authenticate Private Access` |
| Content tech | Embedded webviews (Netskope form, then Microsoft IdP) |

**Implication:** Window discovery must not filter to standard document windows only. Prefer observing the application’s AX hierarchy / `NSWorkspace` + Accessibility windows for that PID.

## 2. Shared tree patterns

Both steps search the focused (or main) Netskope window’s AX subtree (depth-limited DFS, ~25 levels in the Lua script).

### Email field

| Role accepted | Notes |
|---------------|--------|
| `AXTextField` | Preferred |
| `AXTextArea` | Also accepted (webview quirks) |

Selection rule in current automation: **first** matching text field/area in DFS order. This has been sufficient in practice; if multiple fields appear, Phase 2 should prefer:

1. Focused field (`AXFocused`)
2. Field with email-related `AXPlaceholderValue` / `AXDescription`
3. First enabled editable field

### Actions

| Step | Preferred action | AX signal |
|------|------------------|-----------|
| 1 | Press Continue | `AXButton` where `AXTitle` or `AXDescription` matches `/continue/i` (case-insensitive) |
| 1 enable gate | Wait before press | `AXEnabled == true` on that button |
| 2 | Submit | Keyboard Return to Netskope process (Microsoft form accepts Enter) |
| 2 detect | Page identity | `AXButton` `/next/i` **or** `AXStaticText`/`AXHeading` value/title `/sign in/i` |

Attribute access must coerce values with string conversion before regex — `AXValue` can be numeric and crash naive string ops (learned in Lua).

## 3. Step 1 — Netskope identity page

### Reliable selectors

| Purpose | Selector strategy | Confidence |
|---------|-------------------|------------|
| Email field | First `AXTextField`/`AXTextArea` under window | High (production-proven) |
| Continue | `AXButton` title/description ∋ `continue` | High |
| Ready to continue | That button’s `AXEnabled` | High |

### Unsafe / insufficient approaches

| Approach | Result |
|----------|--------|
| Set `AXValue` on the field to the email | **Fails** — webview JS does not receive input events; Continue stays disabled |
| Press Return / Enter to submit | **Fails** — does not activate Continue on Netskope page |
| Screen coordinates only | Works as fallback but brittle across resolutions/layouts |

### Safe input strategy

1. `AXFocused = true` on the field (or click field fallback).
2. Process-targeted `Cmd+A`, then type characters via `CGEvent` / equivalent posted **to the Netskope PID**.
3. Poll `AXEnabled` on Continue; then `AXPress` (not a synthetic click unless fallback).

### Coordinate fallback (window frame fractions)

Measured for the known layout; use only if AX lookup fails:

| Target | X fraction | Y fraction |
|--------|------------|------------|
| Email field | 0.50 | 0.68 |
| Continue | 0.50 | 0.78 |

## 4. Step 2 — Microsoft (Kiatnakin Phatra) sign-in page

### Page detection (not coordinates)

Poll until any of:

- Button: title/description contains `next`
- Static text / heading: value/title contains `sign in`

Timeout used in production: **20s** at **0.3s** poll interval.

### Reliable selectors

| Purpose | Selector strategy | Confidence |
|---------|-------------------|------------|
| Email field | Same as Step 1 (first text field/area) | High |
| Submit | Return key to Netskope process | High |
| Alternate submit | `AXPress` on Next button | Medium (Enter preferred; button used for detection) |

### Coordinate fallback

| Target | X fraction | Y fraction |
|--------|------------|------------|
| Email field | 0.50 | 0.24 |

(Different vertical position than Step 1 — layouts are not interchangeable.)

## 5. Direct AX value vs keyboard input — decision

| Operation | Use AX value assignment? | Use keyboard / AX action? |
|-----------|--------------------------|---------------------------|
| Focus field | Yes (`AXFocused`) | Optional click fallback |
| Insert email into webview field | **No** | **Yes** — real keystrokes to Netskope |
| Clear field | Prefer `Cmd+A` then type | Avoid assuming `AXValue = ""` fires events |
| Continue (Step 1) | N/A | **`AXPress`** when enabled |
| Next / submit (Step 2) | N/A | **Return** (primary); `AXPress` Next as secondary |

**Rule:** Accessibility is for **discovery, focus, enablement, and button press**. Character entry into Netskope/Microsoft webviews must be **keyboard events targeted at the Netskope process**.

## 6. Process-targeted events

Hammerspoon’s fix for typing into the wrong app:

- Wrong: global `keyStrokes(email)` — can hit Chat/IDE if focus races.
- Right: `keyStrokes(email, netskopeApp)` — events delivered to that app.

Native equivalent: create `CGEvent` keyboard events and post them to the Netskope Client process (`CGEventPostToPid` or focus + careful posting after confirming frontmost is Netskope). Phase 2 ADR chooses the concrete API; requirement is **no leakage to unrelated apps**.

## 7. Timing constants proven in production

| Constant | Value | Role |
|----------|-------|------|
| Post-focus delay | 0.4s | Let AX/webview settle |
| Post-Continue watch start | 1.5s after Step 1 start path | Begin Microsoft poll |
| Microsoft poll interval | 0.3s | Page detection |
| Microsoft poll timeout | 20s | Bound wait |
| Continue enable poll | 0.4s × 8 | Bound wait for enabled |
| Sequence cooldown | 30s | De-dupe window events |
| Initial delay after trigger | 1.0s | Window settle |

These are starting values for the native port, not hard product requirements — adjust with telemetry but keep bounds.

## 8. Phase 2 validation checklist (live tree)

When the re-authenticate window is open, capture (redact emails):

- [ ] Full AX dump of the Netskope window for Step 1
- [ ] Confirm Continue button role/title/`AXEnabled` transitions after keystrokes
- [ ] Full AX dump after navigation to Microsoft page
- [ ] Confirm Next / Sign in nodes and email field roles
- [ ] Verify `CGEventPostToPid` (or chosen API) does not deliver to other apps when Netskope is not frontmost
- [ ] Re-test after Netskope Client upgrades (track version `CFBundleShortVersionString`)

## 9. Acceptance mapping

| Phase 1 acceptance criterion | Covered by |
|------------------------------|------------|
| Identify both pages without coordinates only | §§3–4 selectors + page detection |
| Direct input to Netskope only | §6 |
| Bounded retries / manual recovery | Timing table + FR-8 in functional requirements |
| No passwords/tokens | Fields are email-only; no AX reads of secure fields |
| Works without Hammerspoon | Native AX + CGEvent plan in ADR |
