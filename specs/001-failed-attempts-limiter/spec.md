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

5. **Given** the user is in `AppLocked` state (session expired due to backgrounding)
   with 0 prior failed attempts,
   **When** they fail biometric authentication 5 times consecutively from the locked screen,
   **Then** the app enters `AuthRateLimited` (the attempt-based lockout supersedes the
   lifecycle lock; `_preLockoutContext` is set to `lifecycleLock`).

6. **Given** the user is on the authentication screen,
   **When** they cancel the biometric prompt (dismiss without attempting),
   **Then** the failed attempt counter is NOT incremented and the authentication button
   remains available.

7. **Given** the user is on the authentication screen,
   **When** a hardware-unavailable or enrollment-missing error occurs,
   **Then** the failed attempt counter is NOT incremented. If the current state was
   `AppLocked`, the cubit returns to `AppLocked` (not `Unauthenticated`).

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

4. **Given** the app is in `AuthRateLimited` with 5 seconds remaining,
   **When** the user backgrounds the app and the lockout expires while the app is
   in the background,
   **When** the user resumes the app,
   **Then** the lockout screen is NOT shown — the app displays the normal authentication
   screen (or `AppLocked` if `_preLockoutContext` was `lifecycleLock`).

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
   **Then** the duration resets to 60 seconds (first-level lockout). The escalation reset
   (level → 0) is also persisted to secure storage so that a subsequent force-kill and
   relaunch also results in a 60-second first lockout.

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

4. **Given** the user was in `AppLocked` state and triggered `AuthRateLimited` with
   20 seconds remaining,
   **When** the app is force-closed and relaunched,
   **Then** the lockout screen shows approximately 20 seconds remaining. When the lockout
   expires, the app transitions to `Unauthenticated` (cold-start rule: `_preLockoutContext`
   is not persisted and defaults to `unauthenticated` on relaunch — NOT `AppLocked`).

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
- What happens when the app is backgrounded (not killed) while `AuthRateLimited` is
  active? `_preLockoutContext` is preserved in memory; `Timer.periodic` may not fire
  reliably on mobile in background. Remaining time is always computed from the persisted
  `_lockoutStartMs` (absolute start time), so missed ticks do not accumulate error. On
  foreground resume the next tick immediately corrects any display lag. FR-015 ensures
  `handleAppResumed()` does not emit `AppLocked` during an active lockout.
- What is the timer mechanism when the app is backgrounded? The system MUST use
  `_lockoutStartMs` (absolute timestamp) to compute `remainingSeconds` on every tick —
  not a decrement-by-one approach — so that background time is counted correctly
  regardless of whether `Timer.periodic` fires in background (FR-003, US2 Scenario 3).
- What happens to counter-increment and escalation-increment atomicity? Both operations
  (increment `_failedAttemptCount` to threshold, increment `_escalationLevel`) occur
  synchronously in the same event handler with no intermediate state observable between
  them.
- What happens when the rate-limit timer expires and the prior lock was a lifecycle lock
  (`AppLocked`)? The app transitions back to `AppLocked` — not `Unauthenticated`. The
  lifecycle lock remains in effect until the user successfully authenticates. **Exception
  (cold start)**: if the app was force-killed while `AuthRateLimited` was active, the
  prior context is not persisted and defaults to `unauthenticated` on relaunch. The app
  transitions to `Unauthenticated` when the lockout expires, not `AppLocked`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST track the number of consecutive failed biometric authentication
  attempts.
- **FR-002**: After exactly 5 consecutive failed attempts, the system MUST transition
  directly to the `AuthRateLimited` state, preventing further authentication attempts.
  The lockout-triggering (5th) failure MUST NOT first emit `AuthError` — the transition
  goes directly from `AuthLoading` to `AuthRateLimited`. The first four failures emit
  `AuthError` as per the existing failed-attempt path.
- **FR-003**: During lockout, the system MUST display the remaining wait time to the user,
  updated every second. The displayed `remainingSeconds` value MUST be clamped to
  [0, lockoutDurationSeconds] and MUST NOT be negative.
- **FR-004**: The failed attempt counter MUST reset to 0 upon a successful authentication.
- **FR-005**: The failed attempt counter MUST reset to 0 when the lockout duration expires.
  The escalation level (FR-007) is NOT reset on expiry — it persists until a successful
  authentication.
- **FR-006**: The lockout duration MUST follow an exponential backoff schedule indexed by
  escalation level: level 0 → 60 s, level 1 → 120 s, level 2 → 240 s, level 3+ → 900 s
  (cap). The escalation level index MUST be clamped to the last tier (level 3); any
  lockout event beyond level 3 uses 900 s indefinitely.
- **FR-007**: The escalation level (which determines the next lockout duration) MUST reset to
  level 0 ONLY upon successful authentication. Lockout expiry (FR-005) does NOT reset the
  escalation level.
- **FR-008**: The lockout state MUST be persisted to secure storage so it survives app
  termination. Persisted fields: lockout start timestamp, total lockout duration, current
  escalation level, and consecutive failed attempt count. Remaining time on restore is
  computed as `total duration − (now − start timestamp)`.
- **FR-009**: On app launch, the system MUST restore any active lockout state and continue
  counting down from the correct remaining time. On cold-start restore, the prior-context
  flag (`_preLockoutContext`) defaults to `unauthenticated` — a prior lifecycle lock context
  is not assumed to carry over after a forced restart (see cold-start exception in Edge Cases).
- **FR-010**: A cancelled authentication attempt (user dismisses the biometric prompt) MUST
  NOT increment the failed attempt counter.
- **FR-011**: A hardware-unavailable or enrollment-missing event MUST NOT increment the
  failed attempt counter. When such an event occurs while the cubit state is `AppLocked`,
  the cubit MUST remain in `AppLocked` (not transition to `Unauthenticated`).
- **FR-012**: The lockout MUST be represented as the `AuthRateLimited` state — a distinct,
  typed state in the authentication state machine (not conflated with `AuthError`,
  `Unauthenticated`, or `AppLocked`). A private `_preLockoutContext` flag MUST be set to
  `lifecycleLock` when lockout is triggered while cubit state is `AppLocked`, and to
  `unauthenticated` otherwise. The only valid exit from `AuthRateLimited` is countdown
  expiry (FR-013). Force-closing the app, hardware errors, and lifecycle backgrounding
  do NOT exit the lockout state.
- **FR-013**: When the `AuthRateLimited` countdown reaches zero, the system MUST transition
  to `AppLocked` if `_preLockoutContext` is `lifecycleLock`, or to `Unauthenticated` if
  `_preLockoutContext` is `unauthenticated`.
- **FR-014**: Biometric hardware becoming unavailable during an active `AuthRateLimited`
  lockout MUST NOT reset, cancel, or bypass the lockout. The `AuthRateLimited` state
  remains active until the countdown expires normally.
- **FR-015**: While `AuthCubit` is in `AuthRateLimited` state, the `handleAppResumed()`
  lifecycle callback MUST NOT emit `AppLocked`. The active lockout supersedes the
  lifecycle auto-lock until the countdown expires. (`_shouldRequireAuth()` naturally
  returns false for non-`Authenticated` states, satisfying this requirement without
  additional branching.)

### Key Entities

- **Failed Attempt Record**: Tracks current consecutive failed count, current escalation
  level, and the timestamp when the active lockout began (if any).
- **Lockout Policy**: Defines the maximum attempts threshold (default: 5) and the duration
  schedule per escalation level.
- **Lockout State**: Carries the remaining duration and escalation level for display and
  enforcement. Persisted as: start timestamp + total duration (remaining recomputed on
  restore); escalation level; consecutive failed count.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can complete all 5 allowed failed attempts and trigger the lockout in
  under 60 seconds of interaction time. (Derives from FR-002: threshold is 5 consecutive
  failures with no artificial delay between attempts.)
- **SC-002**: The countdown display refreshes at least once per second with no visible lag
  during the lockout period. (Derives from FR-003: remaining time updated every second.)
- **SC-003**: After a successful authentication, the app accepts the next attempt immediately
  with no residual lockout state. "Residual lockout state" means: active lockout fields
  (`lockoutStartMs`, `lockoutDurationSeconds`), failed attempt count (FR-004), and
  escalation level (FR-007) are all cleared to zero on success.
- **SC-004**: An attacker force-closing and relaunching the app during a lockout is unable
  to bypass the remaining wait time.
- **SC-005**: The lockout duration caps at 15 minutes regardless of how many successive
  lockout events occur.
- **SC-006**: 100% of authentication attempts made during an active lockout are blocked
  without presenting a biometric prompt.

## Clarifications

### Session 2026-04-14

- Q: After rate-limit lockout expires and the user was in `AppLocked` state when they exhausted attempts, which state does the app return to? → A: `AppLocked` — the lifecycle lock remains in effect; the user must still re-authenticate. The rate-limit timer expiry only re-enables the authentication button within the `AppLocked` screen. **Exception (cold start)**: see FR-009 and Edge Cases cold-start note.
- Q: What is the canonical name for the new attempt-based lockout auth state? → A: `AuthRateLimited` — follows the existing `Auth`-prefix convention (`AuthLoading`, `AuthError`, `AuthInitial`) and is used consistently across all spec references.
- Q: What data should be persisted to calculate remaining lockout time on app restart? → A: Lockout start timestamp + total duration. Remaining time is computed as `duration − (now − start)` on restore, correctly accounting for elapsed off-time.

### Session 2026-04-15

- Q: Is `_preLockoutContext` preserved during a background/resume cycle (app not killed)? → A: Yes — it is held in memory only. If the app is backgrounded while `AuthRateLimited` is active but not killed, `_preLockoutContext` stays in memory and the timer continues (or is corrected on resume via `_lockoutStartMs`). Only a force-kill loses the context.
- Q: Are the failed-attempt increment and escalation-level increment atomic? → A: Yes — both occur in a single synchronous event handler on the threshold-triggering failure. No intermediate state is observable between them.
- Q: What timer mechanism ensures background time is counted? → A: `remainingSeconds` on every tick is computed as `lockoutDurationSeconds − ((now − _lockoutStartMs) / 1000)`, not by decrementing. This means missed ticks in background do not cause drift — the next tick recomputes from the absolute start timestamp.
- Q: Does `handleAppResumed()` need an explicit `AuthRateLimited` guard? → A: No. The existing `_shouldRequireAuth()` already returns false for any non-`Authenticated` state, including `AuthRateLimited`. FR-015 is satisfied without additional branching.

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
  (`AuthRateLimited`) are independent mechanisms. When `AuthRateLimited` timer expires
  after a sequence that began from `AppLocked`, the app returns to `AppLocked` — not
  `Unauthenticated`.
- The exponential backoff schedule is: level 0 → 60 s, level 1 → 120 s, level 2 → 240 s,
  level 3+ → 900 s (cap). These values are internal constants, not user-configurable in v1.
- Logging of failed attempts for analytics/security audit is deferred to a follow-up
  feature; this spec covers only enforcement and UX.
