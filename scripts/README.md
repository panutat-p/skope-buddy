# scripts/

## netskope-autofill.swift

Native Swift CLI (AX API + CGEvents, no external dependencies). A standing watcher with a two-state menu-bar icon (indigo `moon.zzz.fill` = idle, yellow `bolt.fill` = watching) for the process lifetime. Credentials come only from project-root `.env`.

### Setup

1. Grant **Accessibility** to Terminal (or iTerm) in System Settings → Privacy & Security → Accessibility.
2. Start the watcher first (see below); open the Netskope **Re-authenticate Private Access** window whenever it appears.

### Run

```bash
./scripts/netskope-autofill.swift

# or compile
swiftc -o /tmp/netskope-autofill scripts/netskope-autofill.swift
/tmp/netskope-autofill
```

Values load from project-root `.env` (gitignored):

| Variable | Page |
|----------|------|
| `NETSKOPE_EMAIL` | First (Netskope) |
| `CORPORATE_EMAIL` | Second (Microsoft / corporate) |
| `CORPORATE_PASSWORD` | Third (password) — stored and typed in plaintext; see caveat below |

### Safety behavior

- **Idle is event-driven.** Between prompts the process sleeps until Netskope launches/activates or an AX window event fires (plus a 60s safety check). After a wake it burst-polls ~20s while the webview loads, then sleeps again. Step 2/3 still poll at 0.3s for up to 20s only during an active sequence.
- **Waits for the right page instead of assuming timing.** Nothing is typed until the target element is present.
- Refuses to run if either email is still the built-in placeholder (`you@kkpfg.com` / `you@phatrasec.com`) or empty — set them in `.env` first.
- Refuses to run if `CORPORATE_PASSWORD` is empty — set it in `.env` first.
- MFA approval, if prompted after step 3, is never automated — that stays manual.

### Caveat: plaintext password

`CORPORATE_PASSWORD` is stored in `.env` as plaintext (matching the other credentials in that file) and typed into the Microsoft password field. `.env` is gitignored and never committed, but it is not encrypted at rest — anything with read access to this file/machine can read the password.
