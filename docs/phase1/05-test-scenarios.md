# Test Scenarios and Acceptance Criteria

**Phase:** 1  
**Maps to:** `.todo/phase1.md` acceptance criteria and FR/NFR in `01-functional-requirements.md`

## 1. Phase 1 gate (documentation / feasibility)

| ID | Criterion | How verified in Phase 1 | Result |
|----|-----------|-------------------------|--------|
| P1-A | Both sign-in pages identifiable without coordinates only | Documented AX selectors + Microsoft markers in `02-accessibility-findings.md` | **Met** (pending live AX dump in Phase 2) |
| P1-B | Input directed to Netskope without affecting unrelated apps | Process-targeted keystroke decision (Hammerspoon-proven + ADR D4/D5) | **Met** as design; runtime proof in Phase 2 |
| P1-C | Failure states have bounded retries + manual recovery | FR-8 timeouts/polls/cooldown + manual menu/hotkeys | **Met** in requirements |
| P1-D | No passwords or auth tokens captured/stored | FR-10, ADR D6, distribution privacy section | **Met** |
| P1-E | Approach works without Hammerspoon | ADR-001 Swift/AX/CGEvent | **Met** as approach |

## 2. Scenarios for Phase 2+ implementation QA

### Happy path

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| S01 | Auto sequence | Trigger Netskope re-authenticate; app trusted | Step1 email → Continue → detect Microsoft → Step2 email → Enter; MFA left to user |
| S02 | Timing | Measure from window appear to Step2 submit | Microsoft detection without fixed multi-second blind sleep; cooldown 30s after |
| S03 | Email config | Set custom emails in Settings | Those strings typed, not defaults |

### Detection and AX

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| S10 | Step1 selectors | Inspect/log AX during Step1 | Continue matched by title/description; field focused via AX |
| S11 | Continue enable gate | Fill via keystrokes | Continue presses only after `AXEnabled` or bounded fallback |
| S12 | Microsoft detect | After Continue | Transition on Next or “Sign in” text within 20s |
| S13 | No coordinate dependency | Disable coordinate fallback in a test build | Happy path still succeeds on reference layout |

### Input safety

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| S20 | Foreign focus | Bring Slack/Cursor frontmost mid-type | No characters appear there; sequence aborts or re-focuses Netskope per FR-6 |
| S21 | Target PID | Instrument event poster | Events target Netskope Client PID only |
| S22 | AXValue ban | Attempt assignment in a debug probe | Confirm Continue stays disabled (documents why keystrokes are required) |

### Failure and recovery

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| S30 | No window | Manual run with Netskope closed | Skip + log; Idle |
| S31 | Microsoft timeout | Block network / force no page change | After 20s: recovery or documented best-effort Step2; no infinite poll |
| S32 | Continue never enables | Stub disabled button | Bounded polls → one fallback → Recovery |
| S33 | Cooldown | Burst of window events | Single automatic sequence per 30s |
| S34 | Manual recovery | After Recovery | Menu “Run sequence” works |
| S35 | Step hotkeys | `⌘⌥1` / `⌘⌥2` | Run only that step |

### Permissions and privacy

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| S40 | First launch | Fresh TCC | Onboarding; no keystrokes until granted |
| S41 | Revoke AX | Disable in System Settings while Idle | Autofill pauses; clear status |
| S42 | Log inspection | Complete a run | Logs show states/titles; no password; emails optionally redacted |
| S43 | Preference store | Read defaults DB | Only emails + prefs; no tokens |

### Platform

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| S50 | macOS 14 / 15 | Run on supported OS | Feature parity |
| S51 | Netskope version note | Record client `CFBundleShortVersionString` | Documented alongside test run |
| S52 | Launch at login | Enable, reboot | Agent starts; AX still trusted |

## 3. Acceptance criteria (implementation release)

A build is acceptable for internal use when:

1. **S01** passes three times in a row on a reference Mac.
2. **S13** and **S21** pass (identity without coordinates-only; no cross-app typing).
3. **S31–S34** pass (bounded failure + manual path).
4. **S40–S42** pass (permission UX + no secret storage).
5. Hammerspoon script is not required to be loaded for any of the above.

## 4. Traceability to Hammerspoon v7

| Hammerspoon behavior | Scenario |
|----------------------|----------|
| Window filter + allowRoles | S01, FR-1 |
| AX field + keystrokes + Continue AXPress | S10–S11 |
| Microsoft poll 0.3s / 20s | S12, S31 |
| Enter on Step2 | S01 |
| 30s lastFired cooldown | S33 |
| ⌘⌥1 / ⌘⌥2 | S35 |
| Process-targeted strokes | S20–S21 |
