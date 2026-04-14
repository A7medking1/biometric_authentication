# Implementation Plan: Failed Attempts Limiter

**Branch**: `001-failed-attempts-limiter` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/001-failed-attempts-limiter/spec.md`

## Summary

Add exponential-backoff rate limiting to `AuthCubit`: track consecutive failed
biometric attempts, lock the user out for a configurable duration (60 s → 120 s →
240 s → 900 s cap) when the threshold (5) is reached, show a live countdown in
`AuthScreen`, and persist the lockout state to encrypted secure storage so
force-killing the app cannot bypass the wait. A new `AuthRateLimited` state drives
all UI and cubit logic; a new `RateLimitStorageService` wraps `flutter_secure_storage`.

## Technical Context

**Language/Version**: Dart 3.9+ / Flutter 3.x (SDK constraint `^3.9.0`)
**Primary Dependencies**: flutter_bloc ^8.1.6, equatable ^2.0.5, local_auth ^3.0.0,
  flutter_secure_storage ^9.2.2 (new — to be added)
**Storage**: flutter_secure_storage (Android Keystore AES-256 GCM / iOS Keychain /
  Windows DPAPI)
**Testing**: flutter_test (built-in)
**Target Platform**: Android (API 23+), iOS 10+, Windows
**Project Type**: Mobile/desktop app
**Performance Goals**: Countdown UI ≤ 1-second refresh latency; no jank during
  `Timer.periodic` ticks
**Constraints**: Offline-capable; no network dependency; Android minSdk bump to 23
  required by `flutter_secure_storage`
**Scale/Scope**: Single authenticated user per device install

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-Design Status | Post-Design Status |
|-----------|------------------|--------------------|
| I. Security-First Authentication | ✅ `AuthRateLimited` blocks all auth attempts during lockout — no bypass path | ✅ Confirmed: `authenticate()` short-circuits when `_isLockedOut()` |
| II. Platform Abstraction | ✅ `RateLimitStorageService` wraps `flutter_secure_storage`; `LocalAuthService` unchanged | ✅ Confirmed: no direct plugin calls in cubit |
| III. Explicit State Machine | ✅ `AuthRateLimited` is a typed subclass; all transitions documented | ✅ Confirmed: see `data-model.md` state machine diagram |
| IV. Lifecycle Integrity | ✅ `AuthRateLimited` is independent from `AppLocked`; coexistence rule clarified | ✅ `_preLockoutContext` determines successor state on timer expiry |
| V. Test-Driven State Logic | ✅ Unit tests for all cubit transitions required before merge | ✅ Test file paths identified in quickstart.md |

**No violations. No Complexity Tracking entries required.**

## Project Structure

### Documentation (this feature)

```text
specs/001-failed-attempts-limiter/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
lib/
├── main.dart                          # No changes
├── local_auth_service.dart            # No changes
├── services/
│   └── rate_limit_storage_service.dart  # NEW — secure storage wrapper
├── blocs/
│   ├── auth_state.dart                # MODIFY — add AuthRateLimited class
│   └── auth_cubit.dart                # MODIFY — add rate-limit logic + timer
├── widgets/
│   ├── auth_gate.dart                 # No changes
│   └── lifecycle_manager.dart         # No changes
└── screens/
    └── auth_screen.dart               # MODIFY — add AuthRateLimited UI branch

test/
├── blocs/
│   └── auth_cubit_rate_limit_test.dart  # NEW — cubit unit tests
└── widgets/
    └── auth_screen_rate_limit_test.dart  # NEW — widget tests
```

**Structure Decision**: Single Flutter project (Option 3 — Mobile). No new top-level
directories needed; a `lib/services/` directory is introduced to house
`RateLimitStorageService`, consistent with Flutter project conventions and separating
it from the bloc layer.
