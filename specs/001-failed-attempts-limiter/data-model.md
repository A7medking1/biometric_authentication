# Data Model: Failed Attempts Limiter

**Feature**: `001-failed-attempts-limiter`
**Date**: 2026-04-14

---

## Entities

### `RateLimitRecord`

Represents the persisted lockout state. Read from secure storage on app launch;
written after every failed attempt and every lockout event.

| Field | Type | Description |
|-------|------|-------------|
| `failedAttemptCount` | `int` | Consecutive failed attempts (0–5). Resets to 0 on success or lockout expiry. |
| `escalationLevel` | `int` | Index into the backoff schedule (0–3). Stores the **post-increment** value (i.e., the level to be used for the *next* lockout). Resets to 0 on success. On restore, `_escalationLevel` is set from this field so the next lockout uses the correct tier. |
| `lockoutStartMs` | `int?` | `DateTime.now().millisecondsSinceEpoch` at lockout start. `null` when not locked. |
| `lockoutDurationSeconds` | `int?` | Total lockout duration in seconds for the current lockout event. `null` when not locked. |

**Derived field (not stored)**:
- `remainingSeconds` = `lockoutDurationSeconds − ((now_ms − lockoutStartMs) / 1000)`, clamped to [0, lockoutDurationSeconds].

**Validation rules**:
- `failedAttemptCount` ∈ [0, 5]
- `escalationLevel` ∈ [0, 3] (clamped at 3 regardless of actual count of lockout events)
- `lockoutStartMs` and `lockoutDurationSeconds` are either both `null` (no active lockout) or both non-null (active lockout)

**Storage keys** (in `flutter_secure_storage`):

| Key | Stored value |
|-----|-------------|
| `rl_failed_count` | `failedAttemptCount` as decimal string |
| `rl_escalation_level` | `escalationLevel` as decimal string |
| `rl_lockout_start_ms` | `lockoutStartMs` as decimal string, or absent |
| `rl_lockout_duration_s` | `lockoutDurationSeconds` as decimal string, or absent |

---

### `AuthRateLimited` (Auth State)

New `AuthState` subclass emitted by `AuthCubit` when the user is locked out due
to too many failed attempts.

| Field | Type | Description |
|-------|------|-------------|
| `remainingSeconds` | `int` | Seconds until lockout expires. Emitted anew each tick (≥0). |
| `escalationLevel` | `int` | The escalation level *used for the current lockout* (pre-increment, i.e., the level whose duration is actively counting down). For UI messaging, e.g., "Level 2 lockout". Note: this differs from `RateLimitRecord.escalationLevel`, which stores the post-increment (next) level. |

`Equatable.props`: `[remainingSeconds, escalationLevel]`

---

## Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `kMaxFailedAttempts` | `5` | Threshold before lockout |
| `kLockoutDurationsSeconds` | `[60, 120, 240, 900]` | Backoff schedule (index = escalation level) |

---

## State Machine — Updated Transitions

```
AuthInitial
  └─► AuthLoading ─► Authenticated         (success; resets failedCount + escalation)
                 ─► Unauthenticated         (cancelled; NO counter increment)
                 ─► AuthError               (failed attempt; increments failedCount)
                     └─► [failedCount == kMaxFailedAttempts]
                          └─► AuthRateLimited  (timer ticking; increments escalation)
                               └─► [timer expires]
                                    ├─► AppLocked      (if prior context was lifecycle lock)
                                    └─► Unauthenticated (if prior context was unauthenticated)

Authenticated
  └─► AppLocked  (lifecycle resume after timeout)
       └─► AuthLoading ─► [same as above; failed path → AuthRateLimited]
                                    └─► [timer expires] → AppLocked (prior = lifecycleLock)

BiometricNotAvailable / BiometricNotEnrolled
  (no counter change — hardware/enrollment errors are neutral)
```

---

## Pre-Lockout Context

Private cubit enum (not persisted; derived on restore):

```
enum _PreLockoutContext { lifecycleLock, unauthenticated }
```

Set to `lifecycleLock` when `authenticate()` is called while cubit state is
`AppLocked`. Set to `unauthenticated` otherwise. Used only when transitioning out
of `AuthRateLimited` on timer expiry.

On cold start with an active persisted lockout, the restore logic defaults to
`unauthenticated` (conservative: user must authenticate fresh, not assume a prior
lifecycle lock is still meaningful after a restart).
