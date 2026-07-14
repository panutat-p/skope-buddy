# Phase 1 — Foundation and Feasibility

**Status:** Complete — see [docs/phase1/README.md](../docs/phase1/README.md)

## Goal

Define and validate the native macOS replacement for the existing Hammerspoon-based Netskope sign-in automation before application code is written.

## Scope

- [x] Confirm the Netskope Client bundle identifier and supported macOS versions.
- [x] Inspect the Netskope and embedded Microsoft sign-in accessibility trees.
- [x] Document reliable selectors for both email fields and the Continue/Next actions.
- [x] Validate that targeted keyboard events work with the Netskope process.
- [x] Decide when direct accessibility value assignment is safe and when keyboard input is required.
- [x] Define the login state machine and timeout/retry behavior.
- [x] Define Accessibility permission onboarding and failure messaging.
- [x] Decide the menu-bar interface, settings, logs, manual triggers, and launch-at-login behavior.
- [x] Decide how the two email addresses are stored locally.
- [x] Confirm signing, notarization, and non-sandboxed distribution requirements.

## Proposed state flow

1. Idle
2. Netskope window detected
3. First identity filled
4. Continue activated
5. Waiting for Microsoft sign-in page
6. Second identity filled
7. Form submitted
8. Cooldown or recovery

## Deliverables

- [x] Written functional requirements → `docs/phase1/01-functional-requirements.md`
- [x] Accessibility-tree findings → `docs/phase1/02-accessibility-findings.md`
- [x] Architecture decision record → `docs/phase1/03-architecture-decision-record.md`
- [x] Permission and distribution plan → `docs/phase1/04-permission-distribution-plan.md`
- [x] Test scenarios and acceptance criteria → `docs/phase1/05-test-scenarios.md`
- [x] Phase 2 implementation checklist → `docs/phase1/06-phase2-checklist.md`

## Acceptance criteria

- [x] Both sign-in pages can be identified without depending only on screen coordinates.
- [x] Input can be directed to Netskope without affecting an unrelated foreground application.
- [x] Failure states have bounded retries and can be recovered manually.
- [x] No passwords or authentication tokens are captured or stored.
- [x] The implementation approach works without Hammerspoon.

## Confirmed facts (this Mac)

| Item | Value |
|------|--------|
| Bundle ID | `com.netskope.client.Netskope-Client` |
| Client version | `138.0.2.2681` |
| Agent UI | `LSUIElement = 1` |
| Skope Buddy OS target | macOS 14+ |

## Out of scope

- Swift or application source code
- UI implementation
- Packaging or deployment
- Automatic password or MFA handling

## Next

Phase 2 — [docs/phase1/06-phase2-checklist.md](../docs/phase1/06-phase2-checklist.md)
