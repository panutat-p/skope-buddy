# Skope Buddy

Automates the Netskope Client re-authentication prompt on macOS, which requires three fields typed in sequence:

1. **Netskope** page — `you@kkpfg.com` → Continue
2. **Microsoft (KKPS)** page — `you@phatrasec.com` → Next
3. **Password** page — your KKPS password → Sign in

MFA approval stays manual, by design.

## How to use

1. Copy your credentials into a project-root `.env` (gitignored — see [scripts/README.md](scripts/README.md#caveat-plaintext-password) for the plaintext-storage tradeoff):

   ```bash
   NETSKOPE_EMAIL=you@kkpfg.com
   KKPS_EMAIL=you@phatrasec.com
   KKPS_PASSWORD=...
   ```

2. Grant **Accessibility** to Terminal (or iTerm) in System Settings → Privacy & Security → Accessibility.
3. Run the script, then open the Netskope **Re-authenticate Private Access** window whenever you're ready (the script waits for it indefinitely; `Ctrl+C` cancels):

   ```bash
   ./scripts/netskope-autofill.swift sequence
   ```

Details, all commands, and safety behavior: [scripts/README.md](scripts/README.md).

## Project layout

| Path | What it is |
|------|------------|
| [scripts/netskope-autofill.swift](scripts/netskope-autofill.swift) | Native Swift CLI (AX API + CGEvents) — run this |
| [.spec/phase1.md](.spec/phase1.md) | Phase 1 design record (requirements, AX findings, ADR, permission plan, test scenarios) |
| [.spec/phase2.md](.spec/phase2.md) | Phase 2 — implementation & enhancements checklist (CLI + native menu-bar app) |

## Status

Phase 1 (design/feasibility) is complete — see [.spec/phase1.md](.spec/phase1.md). Current code is the interpreted CLI script; no menu-bar app yet. Open work: [.spec/phase2.md](.spec/phase2.md).
