# scripts/

## netskope-autofill.swift

Native Swift CLI (AX API + CGEvents, no external dependencies). No menu bar yet — run manually when the Netskope re-authenticate window is open.

### Setup

1. Grant **Accessibility** to Terminal (or iTerm) in System Settings → Privacy & Security → Accessibility.
2. Open the Netskope **Re-authenticate Private Access** window — or just start the script first (see below) and open it afterward.

### Run

```bash
# interpreted — start this, then open the Netskope window; it waits for it
./scripts/netskope-autofill.swift sequence \
  --email1 you@kkpfg.com \
  --email2 you@phatrasec.com \
  --password '...'

# or compile
swiftc -o /tmp/netskope-autofill scripts/netskope-autofill.swift
/tmp/netskope-autofill step1 --email1 you@kkpfg.com
/tmp/netskope-autofill step2 --email2 you@phatrasec.com
/tmp/netskope-autofill step3 --password '...'
/tmp/netskope-autofill dump
```

Commands: `sequence` | `step1` | `step2` | `step3` | `dump` | `env`

Values load from project-root `.env` (gitignored):

| Variable | Page |
|----------|------|
| `NETSKOPE_EMAIL` | First (Netskope) |
| `KKPS_EMAIL` | Second (Microsoft / KKPS) |
| `KKPS_PASSWORD` | Third (password) — stored and typed in plaintext; see caveat below |

CLI `--email1` / `--email2` / `--password` override `.env`. `env` just prints what was loaded (no Accessibility needed, and the password value itself is never printed — only `(set)`/`(empty)`).

### Safety behavior

- **Waits for the right page instead of assuming timing.** Every step polls for its target element before typing, so you can start the script *before* opening Netskope:
  - `step1` / `sequence` wait **indefinitely** for the Netskope window and its Continue page to appear — `Ctrl+C` cancels.
  - `step2` and the sequence's step 2 wait up to 20s for the Microsoft page; `step3` / step 3 wait up to 20s for the password page.
  - If the target page never appears, the script aborts (exit 1) instead of typing into whatever page is showing — nothing is typed blind.
- `step1` / `step2` / `sequence` refuse to run if the relevant email is still the built-in placeholder (`you@kkpfg.com` / `you@phatrasec.com`) or empty — set `.env` or pass `--email1`/`--email2` first.
- `step3` / `sequence` refuse to run if `KKPS_PASSWORD` is empty — set `.env` or pass `--password` first.
- MFA approval, if prompted after step 3, is never automated — that stays manual.

### Caveat: plaintext password

`KKPS_PASSWORD` is stored in `.env` as plaintext (matching the other credentials in that file) and typed into the Microsoft password field. `.env` is gitignored and never committed, but it is not encrypted at rest — anything with read access to this file/machine can read the password.
