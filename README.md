# Skope Buddy

Automates the Netskope Client re-authentication prompt on macOS, which requires three fields typed in sequence:

1. **Netskope**
2. **Microsoft**
3. **Password**

MFA approval stays manual, by design.

## How to use

1. Copy your credentials into a project-root `.env`

   ```bash
   NETSKOPE_EMAIL=
   CORPORATE_EMAIL=
   CORPORATE_PASSWORD=
   ```

2. Grant **Accessibility** to Terminal (or iTerm) in System Settings → Privacy & Security → Accessibility.
3. Start the watcher (menu-bar bolt stays up; process sleeps until a Netskope window event). Open **Re-authenticate Private Access** when it appears — fills, 30s cooldown, then idle again. Quit via the menu-bar icon or `Ctrl+C`:

   ```bash
   ./scripts/netskope-autofill.swift
   ```
