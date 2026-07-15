# Skope Buddy

Automates the Netskope Client re-authentication prompt on macOS, which requires three fields typed in sequence:

1. **Netskope**
2. **Microsoft
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
3. Run the script, then open the Netskope **Re-authenticate Private Access** window whenever you're ready (the script waits for it indefinitely; `Ctrl+C` cancels):

   ```bash
   ./scripts/netskope-autofill.swift sequence
   ```
