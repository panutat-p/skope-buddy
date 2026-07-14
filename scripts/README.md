# scripts/

## netskope-autofill.swift

CLI port of `hammer_spoon/netskope-autofill.lua` (v7). No menu bar yet — run manually when the Netskope re-authenticate window is open.

### Setup

1. Grant **Accessibility** to Terminal (or iTerm) in System Settings → Privacy & Security → Accessibility.
2. Open the Netskope **Re-authenticate Private Access** window.

### Run

```bash
# interpreted
./scripts/netskope-autofill.swift sequence \
  --email1 you@kkpfg.com \
  --email2 you@phatrasec.com

# or compile
swiftc -o /tmp/netskope-autofill scripts/netskope-autofill.swift
/tmp/netskope-autofill step1 --email1 you@kkpfg.com
/tmp/netskope-autofill step2 --email2 you@phatrasec.com
/tmp/netskope-autofill dump
```

Commands: `sequence` | `step1` | `step2` | `dump`

Emails load from project-root `.env`:

| Variable | Page |
|----------|------|
| `NETSKOPE_EMAIL` | First (Netskope) |
| `KKPS_EMAIL` | Second (Microsoft / KKPS) |
| `KKPS_PASSWORD` | Stored only — not typed by the script yet |

CLI `--email1` / `--email2` override `.env`.
