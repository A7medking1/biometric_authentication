# Feature Specification: Failed Attempts Limiter

**Feature Branch**: `001-failed-attempts-limiter`
**Created**: 2026-04-14
**Status**: Draft
**Input**: User description: "Failed Attempts Limiter — biometric auth lockout with countdown and exponential backoff"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Lockout After Repeated Failures (Priority: P1)

A user who repeatedly fails biometric authentication (e.g., wrong finger, unrecognized face)
reaches a maximum attempt threshold. The app temporarily blocks further authentication attempts
and displays a clear message explaining how long they must wait before trying again.

**Why this priority**: This is the core security requirement. Without it, an attacker can
make unlimited biometric attempts, defeating the purpose of biometric protection.

**Independent Test**: Can be fully tested by triggering 5 consecutive failed authentication
attempts and verifying the app enters a locked state with an appropriate wait message — no
other feature required.

**Acceptance Scenarios**:

1. **Given** the user is on the authentication screen with 0 prior failed attempts,
   **When** they fail authentication 5 times consecutively,
   **Then** the app enters a temporary lockout state and displays "Too many failed attempts.
   Try again in 60 seconds." (or equivalent countdown message).

2. **Given** the app is in temporary lockout,
   **When** the user attempts to trigger authentication,
   **Then** the attempt is blocked — no biometric prompt is shown — and the remaining
   wait time is displayed.

3. **Given** the app is in temporary lockout,
   **When** the lockout duration expires,
   **Then** the failed attempt counter resets to 0 and the authentication button becomes
   available again.

4. **Given** the app is in temporary lockout and the user successfully authenticates
   after the lockout expires,
   **Then** the failed attempt counter resets to 0 and the authenticated session begins.

---

### User Story 2 - Live Countdown During Lockout (Priority: P2)

While the app is locked due to too many failed attempts, the user sees a live countdown
timer on screen showing exactly how many seconds remain before they can try again.
The timer updates every second without requiring user interaction.

**Why this priority**: A static "try again later" message is frustrating. A live countdown
gives the user a concrete expectation, reducing support requests and improving perceived
fairness of the security measure.

**Independent Test**: Can be tested by triggering lockout, then observing the displayed
remaining-time value decrement every second until it reaches zero and the auth button
re-enables.

**Acceptance Scenarios**:

1. **Given** the app has just entered lockout (e.g., 60-second duration),
   **When** 1 second elapses,
   **Then** the displayed remaining time decreases by 1 second.

2. **Given** the countdown reaches zero,
   **When** the display updates,
   **Then** the lockout message disappears, the failed attempt counter resets, and the
   authentication button becomes interactive.

3. **Given** the app is backgrounded while the countdown is running,
   **When** the user returns before the lockout expires,
   **Then** the countdown resumes from the correct remaining time (i.e., elapsed background
   time is counted).

---

### User Story 3 - Exponential Backoff for Repeated Offenses (Priority: P3)

Each successive lockout event (not each failed attempt, but each time the full attempt
limit is reached) doubles the lockout duration up to a configured maximum. For example:
first lockout = 1 minute, second = 2 minutes, third = 4 minutes, up to 15 minutes maximum.
The escalation level resets after a successful authentication.

**Why this priority**: Simple fixed-duration lockouts can be waited out repeatedly at low
cost. Exponential backoff raises the cost of repeated attacks significantly.

**Independent Test**: Can be tested by triggering the lockout threshold multiple times in
sequence (each time waiting for the lockout to expire before retrying), then verifying
each successive lockout duration doubles until the cap is reached.

**Acceptance Scenarios**:

1. **Given** the user has triggered their first lockout event (5 failed attempts),
   **When** the lockout begins,
   **Then** the duration is 60 seconds.

2. **Given** the user triggered lockout, waited, failed 5 more times (second lockout event),
   **When** the second lockout begins,
   **Then** the duration is 120 seconds (2 minutes).

3. **Given** the user has reached the maximum lockout level (e.g., 15 minutes),
   **When** they trigger yet another lockout event,
   **Then** the duration stays at 15 minutes (cap is enforced — no further escalation).

4. **Given** the user is at escalation level 3 and successfully authenticates,
   **When** they next fail 5 times (new lockout event),
   **Then** the duration resets to 60 seconds (first-level lockout).

---

### User Story 4 - Secure Persistence of Lock State (Priority: P4)

The lockout state (remaining time, escalation level, failed attempt count) is preserved
if the app is force-closed or the device is rebooted while a lockout is active. When the
user reopens the app, the lockout resumes for the remaining duration.

**Why this priority**: Without persistence, force-closing the app becomes a trivial way to
bypass the lockout, completely defeating its security purpose.

**Independent Test**: Can be tested by triggering lockout, force-killing the app,
relaunching, and verifying the correct remaining lockout time is shown.

**Acceptance Scenarios**:

1. **Given** the app is in a 60-second lockout with 30 seconds remaining,
   **When** the app is force-closed and reopened,
   **Then** the lockout screen shows approximately 30 seconds remaining (accounting for
   elapsed real time since closure).

2. **Given** the app is force-closed and the lockout duration expires while closed,
   **When** the user reopens the app,
   **Then** the app shows the normal authentication screen (lockout already expired).

3. **Given** the app is force-closed and relaunched during lockout,
   **When** the user attempts to authenticate,
   **Then** the attempt is blocked for the remaining lockout duration.

---

### Edge Cases

- What happens when biometric hardware becomes unavailable mid-lockout (e.g., sensor error)?
  The lockout MUST still be enforced — hardware error does not reset the lockout state.
- How does the system handle the app being backgrounded during a lockout? Elapsed time
  MUST continue counting while the app is in the background.
- What if the device clock is changed manually while a lockout is active? The system MUST
  use elapsed duration tracking rather than absolute end timestamps to resist clock manipulation.
- What if the app is uninstalled and reinstalled? Persisted lockout state should be cleared
  on reinstall (this is expected platform behavior for secure storage).
- What if the max-attempts threshold is reached during an already-active lockout? This
  scenario cannot occur (attempts are blocked during lockout), so no additional handling
  is required.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST track the number of consecutive failed biometric authentication
  attempts.
- **FR-002**: After exactly 5 consecutive failed attempts, the system MUST enter a temporary
  lockout state preventing further authentication attempts.
- **FR-003**: During lockout, the system MUST display the remaining wait time to the user,
  updated every second.
- **FR-004**: The failed attempt counter MUST reset to 0 upon a successful authentication.
- **FR-005**: The failed attempt counter MUST reset to 0 when the lockout duration expires.
- **FR-006**: The lockout duration MUST follow an exponential backoff schedule: 60 s → 120 s
  → 240 s, capped at 900 s (15 minutes).
- **FR-007**: The escalation level (which determines the next lockout duration) MUST reset to
  the lowest level upon successful authentication.
- **FR-008**: The lockout state (remaining seconds, escalation level, failed count) MUST be
  persisted to secure storage so it survives app termination.
- **FR-009**: On app launch, the system MUST restore any active lockout state and continue
  counting down from the correct remaining time.
- **FR-010**: A cancelled authentication attempt (user dismisses the biometric prompt) MUST
  NOT increment the failed attempt counter.
- **FR-011**: A hardware-unavailable or enrollment-missing event MUST NOT increment the
  failed attempt counter.
- **FR-012**: The lockout state MUST be represented as a distinct, typed state in the
  authentication state machine (not conflated with existing error or unauthenticated states).

### Key Entities

- **Failed Attempt Record**: Tracks current consecutive failed count, current escalation
  level, and the timestamp when the active lockout began (if any).
- **Lockout Policy**: Defines the maximum attempts threshold (default: 5) and the duration
  schedule per escalation level.
- **Lockout State**: Carries the remaining duration and escalation level for display and
  enforcement.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can complete all 5 allowed failed attempts and trigger the lockout in
  under 60 seconds of interaction time.
- **SC-002**: The countdown display refreshes at least once per second with no visible lag
  during the lockout period.
- **SC-003**: After a successful authentication, the app accepts the next attempt immediately
  with no residual lockout state.
- **SC-004**: An attacker force-closing and relaunching the app during a lockout is unable
  to bypass the remaining wait time.
- **SC-005**: The lockout duration caps at 15 minutes regardless of how many successive
  lockout events occur.
- **SC-006**: 100% of authentication attempts made during an active lockout are blocked
  without presenting a biometric prompt.

## Assumptions

- The maximum number of allowed consecutive failed attempts before lockout is 5; this value
  may be made configurable in a follow-up iteration but is treated as a constant for v1.
- A "failed attempt" is defined exclusively as an `AuthResult.failed` outcome from the
  biometric service. `cancelled`, `notAvailable`, and `notEnrolled` outcomes are neutral —
  they do not count toward the threshold.
- Secure storage is available on all supported platforms (Android Keystore / iOS Keychain).
  If secure storage is unavailable at runtime, the lockout state falls back to in-memory
  only (lockout is still enforced for the current session, but does not persist across
  restarts).
- Existing lifecycle-based auto-lock (`AppLocked`) and the new attempt-based lockout
  (`AuthRateLimited`) are independent mechanisms and MUST NOT conflict.
- The exponential backoff schedule is: level 0 → 60 s, level 1 → 120 s, level 2 → 240 s,
  level 3+ → 900 s (cap). These values are internal constants, not user-configurable in v1.
- Logging of failed attempts for analytics/security audit is deferred to a follow-up
  feature; this spec covers only enforcement and UX.
