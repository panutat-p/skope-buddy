# Permission and Distribution Plan

**Phase:** 1  
**Related ADR:** ADR-001 (D7, D8)

## 1. Permissions required

### 1.1 Accessibility (required)

| Item | Detail |
|------|--------|
| TCC right | Accessibility (`kTCCServiceAccessibility`) |
| Why | Read Netskope AX tree; focus fields; `AXPress`; observe UI |
| Check API | `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions` |
| Prompt | Use `AXIsProcessTrustedWithOptions` with prompt option once; also deep-link to System Settings |
| Settings path | System Settings → Privacy & Security → Accessibility → enable **Skope Buddy** |

**Onboarding copy (draft):**

> Skope Buddy needs Accessibility access to fill your email on the Netskope sign-in window. Your password and MFA codes are never entered or stored. Open Settings, enable Skope Buddy, then return here.

**Failure messaging (draft):**

| State | Message |
|-------|---------|
| Not granted | “Accessibility is off — autofill paused.” Menu: Open System Settings |
| Granted then revoked | “Accessibility was turned off. Autofill stopped.” |
| Trusted but AX attach fails | “Could not read the Netskope window. Try Manual Run or check Netskope is showing Re-authenticate.” |

While untrusted: no `CGEvent` posting; menu shows blocked state.

### 1.2 Automation / AppleEvents

**Not required** for the Hammerspoon-equivalent design (AX + CGEvent). Do not request Automation permission unless a future feature uses AppleScript.

### 1.3 Input Monitoring

**Not required** if we only *post* events to a PID and do not tap global keystreams. Prefer post-to-PID over event taps to avoid an extra TCC prompt.

### 1.4 Notifications (optional)

Optional `UserNotifications` for Recovery / success. If used: standard notification authorization prompt; failure of notification permission must not block autofill.

### 1.5 Login Item

`SMAppService` registration for launch-at-login. User can also remove the item from System Settings → General → Login Items. Default: **off**.

## 2. Entitlements and sandbox

| Setting | Value | Reason |
|---------|-------|--------|
| App Sandbox | **Disabled** | Controlling another app’s UI is incompatible with sandbox |
| Hardened Runtime | **Enabled** | Required for notarization |
| `com.apple.security.automation.apple-events` | Only if later needed | Avoid by default |
| Camera/Mic/Contacts/etc. | None | Least privilege |

Hardened Runtime may require exception entitlements only if debugging tools need them; production build should use the minimal set that still allows AX (AX is TCC, not an entitlement grant).

## 3. Signing and notarization

| Step | Requirement |
|------|-------------|
| Certificate | Developer ID Application |
| Team | Project Apple Developer team (TBD at packaging) |
| Runtime | Hardened Runtime on |
| Notarize | `notarytool` submit of the signed `.app` or `.dmg`/`.pkg` |
| Staple | Staple ticket to the distributed artifact |
| Gatekeeper | Users open via standard first-launch; no “right-click Open” workflow as the primary path |

**Bundle ID (proposed):** `buddy.skope.app` or `com.<org>.skope-buddy` — finalize in Phase 2 project creation; must remain stable so TCC Accessibility grants survive updates.

**Versioning:** Bump `CFBundleShortVersionString` / `CFBundleVersion` every notarized build; document that major binary path changes can require re-granting Accessibility (common on ad-hoc unsigned builds; rare when bundle ID + signing identity stay stable).

## 4. Non-sandboxed distribution channel

| Channel | Decision |
|---------|----------|
| Mac App Store | **No** — sandbox |
| Direct download (notarized DMG/ZIP) | **Yes** — primary |
| Internal pkg via Jamf | **Optional** — preferred on managed Macs |
| Homebrew cask | Optional later |

Include a short IT one-pager (Phase 2 packaging): purpose, bundle ID, publisher, “injects only email keystrokes into Netskope Client,” no password handling.

## 5. Managed Mac / EDR considerations

From Hammerspoon notes: unsigned injectors may be flagged; Hammerspoon was tolerated as a known signed tool.

Mitigations:

1. Ship Developer ID + notarized builds only to end users.
2. Provide bundle ID + code signing team ID to IT for allowlists (Cortex XDR, Jamf).
3. Prefer LaunchAgent/login item via `SMAppService` over unsigned LaunchDaemon scripts.
4. Avoid debugging entitlements in production.
5. Keep behavior narrowly scoped (Netskope PID only) to reduce false-positive risk.

## 6. Privacy commitments (user-facing)

- Stores two email addresses locally in preferences.
- Does not read or write password fields.
- Does not complete MFA.
- Logs UI structure and state, not secrets.

## 7. Acceptance checkpoints (pre-Phase 3 release)

- [ ] Fresh Mac: Accessibility onboarding reaches a working grant
- [ ] Revoking Accessibility immediately stops typing
- [ ] Notarized build opens without Gatekeeper block
- [ ] Login Item toggle survives reboot
- [ ] EDR smoke test on a managed device (if available) before wide rollout
