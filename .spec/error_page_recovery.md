# Netskope Re-auth Error Page — Structure & Recovery

**Status:** Resolved — implemented in `scripts/netskope-autofill.swift`
**Scope:** how the re-authenticate webview's error pages are detected and recovered from.
**Captured:** live AX dump of `Netskope Client` pid 841, window `Re-authenticate Private Access`.

## The page

URL `https://nsauth.goskope.com/nsauth/email/authenticate`, window is an
`AXFloatingWindow` (451×603).

```
AXWindow sub=AXFloatingWindow title="Re-authenticate Private Access"
  AXScrollArea
    AXWebArea desc="Sorry!"
      AXHeading title="Request Timed Out"
      AXHeading title="Please retry"
      AXHeading title="unkn - ERR_TIMEOUT"
    AXScrollBar ×2                        # 8 unlabeled increment/decrement AXButtons
  AXButton help=""       AXIdentifier=_NS:43   # reload  (⟲)
  AXButton help="Close"  AXIdentifier=_NS:33   # close   (✕)
  AXStaticText value="Re-authenticate Private Access"
```

That is the **whole** accessible page. No text field, no Continue, and **no
in-page "Refresh" button** — the illustration below the headings is a static
image. The only recovery control is the reload button in the window chrome.

## Why the first attempt failed

The original recovery keyed on an `AXButton` whose *title + description*
contained `"refresh"`. On this page:

- the reload button has **empty** title, description **and** help text;
- the only attribute distinguishing it from its neighbour is that the
  neighbour's `AXHelp` is `"Close"`;
- neither `AXTitle` nor `AXDescription` was ever going to match.

So `netskopeErrorPageVisible()` returned false, `step1PageReady()` could never
become true (no field, no Continue), and `waitForStep1` looped forever.

`AXCloseButton` / `AXMinimizeButton` / `AXZoomButton` on this window all return
the *same* opaque element, so they cannot be used to identify the chrome either.

## What the fix does

**Detect by page text**, since text is all there is:
`AXWebArea` description starting `"sorry"`, or any `AXHeading` / `AXStaticText`
matching `request timed out`, `err_timeout`, `please retry`, `err_connection`,
`err_internet_disconnected`, `err_name_not_resolved`. Guarded by
`step1PageReady(in:)` first, so a real form is never reloaded out from under us.

**Locate reload by elimination**, over the window's **direct children only** —
recursing matches the scroll bars' 8 unlabeled buttons first. Prefer an
explicitly labeled refresh/reload button if a future build provides one;
otherwise take the sole non-close/minimize/zoom `AXButton`. If the choice is
ambiguous (0 or >1 candidates) return nil rather than press an unknown button in
a login window, and fall back to a positional click at **fx 0.876, fy 0.050** of
the window frame (verified at two different window positions).

**Bounded retries with backoff**: 4 reloads, `attempt × 5s` between failures,
then a 120s pause — a timed-out re-auth usually means the tunnel is down, and
reloading cannot fix that.

## Verified behaviour

- `AXUIElementPerformAction(reloadButton, kAXPressAction)` → returns `.success`,
  webview reloads, step 1 form (`Enter the user email` + `AXTextField` +
  `Continue`) appears after **≈4s**. Hence `errorPageSettleSeconds = 12`.
- On the recovered step 1 page: `step1PageReady` true, `windowShowsErrorPage`
  false (no false positive), reload button still found and still not Close.
