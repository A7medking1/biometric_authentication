# Tasks: Failed Attempts Limiter

**Input**: Design documents from `specs/001-failed-attempts-limiter/`
**Prerequisites**: [plan.md](plan.md) · [spec.md](spec.md) · [data-model.md](data-model.md) · [research.md](research.md)

**Tests**: Included — Constitution Principle V requires unit tests for all cubit transitions before merge.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no blocking dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)
- Exact file paths are included in every description

---

## Phase 1: Setup

**Purpose**: Add the new dependency and satisfy platform requirements so all subsequent phases compile.

- [ ] T001 Add `flutter_secure_storage: ^9.2.2` under `dependencies` in `pubspec.yaml` and run `flutter pub get`
- [ ] T002 Set `defaultConfig { minSdk = 23 }` in `android/app/build.gradle.kts` (was 21; required by `flutter_secure_storage`)

**Checkpoint**: `flutter pub get` succeeds and `flutter build apk` compiles without errors.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared types and wiring that every user story depends on. No story work begins until this phase is complete.

**⚠️ CRITICAL**: All three tasks must be complete before Phase 3 can start.

- [ ] T003 [P] Add `AuthRateLimited` state class to `lib/blocs/auth_state.dart`: fields `final int remainingSeconds` and `final int escalationLevel`; extend `AuthState`; override `Equatable.props` as `[remainingSeconds, escalationLevel]`
- [ ] T004 [P] Create `lib/services/rate_limit_storage_service.dart`: define `RateLimitRecord` class (fields: `failedAttemptCount int`, `escalationLevel int`, `lockoutStartMs int?`, `lockoutDurationSeconds int?`); define storage key constants (`rl_failed_count`, `rl_escalation_level`, `rl_lockout_start_ms`, `rl_lockout_duration_s`); implement `RateLimitStorageService` class with `Future<RateLimitRecord?> loadRecord()`, `Future<void> saveRecord(RateLimitRecord)`, and `Future<void> clearRecord()` backed by `FlutterSecureStorage`
- [ ] T005 Extend `lib/blocs/auth_cubit.dart`: add top-level constants `const int kMaxFailedAttempts = 5` and `const List<int> kLockoutDurationsSeconds = [60, 120, 240, 900]`; add private `enum _PreLockoutContext { lifecycleLock, unauthenticated }`; add `RateLimitStorageService` as a required constructor parameter; add private fields `_failedAttemptCount`, `_escalationLevel`, `_preLockoutContext`, `_lockoutTimer`, `int? _lockoutStartMs`, and `int? _lockoutDurationSeconds` (depends on T003, T004)

**Checkpoint**: `flutter analyze` reports no errors on modified files; all three new constructs are importable.

---

## Phase 3: User Story 1 — Lockout After Repeated Failures (Priority: P1) 🎯 MVP

**Goal**: After 5 consecutive failed biometric attempts the app enters `AuthRateLimited`, blocks further attempts, and shows a lockout message.

**Independent Test**: Launch app → deny biometric prompt 5 times → lockout screen appears with "Too many failed attempts. Try again in 60 seconds." → tapping auth button during lockout shows no biometric prompt.

### Tests for User Story 1 ⚠️ Write these first — they must FAIL before implementation

- [ ] T006 [P] [US1] In `test/blocs/auth_cubit_rate_limit_test.dart`: write failing tests for — (a) each of the first 4 failures increments internal count without emitting `AuthRateLimited` (each emits `AuthError`); (b) the 5th failure emits `AuthRateLimited` directly — no `AuthError` emitted for the 5th attempt; (c) calling `authenticate()` while in `AuthRateLimited` emits no state change and does not call `LocalAuthService.authenticate()`; (d) a `cancelled`, `notAvailable`, or `notEnrolled` outcome does not increment `_failedAttemptCount` and does not advance the count toward lockout (covers FR-010, FR-011); (e) `handleAppResumed()` while in `AuthRateLimited` does NOT emit `AppLocked` (covers FR-015); (f) a `notAvailable` or `notEnrolled` result while cubit state is `AppLocked` returns to `AppLocked`, not `Unauthenticated` (covers FR-011 AppLocked path)
- [ ] T007 [P] [US1] In `test/widgets/auth_screen_rate_limit_test.dart`: write failing test — pumping `AuthScreen` with `AuthRateLimited(remainingSeconds: 45, escalationLevel: 0)` renders a lockout message containing "45" and a disabled (non-tappable) auth button

### Implementation for User Story 1

- [ ] T008 [US1] In `lib/blocs/auth_cubit.dart` `authenticate()` method: on `LocalAuthResult.failed`, increment `_failedAttemptCount`; when `_failedAttemptCount >= kMaxFailedAttempts`, set `_preLockoutContext` based on whether current state is `AppLocked` (→ `lifecycleLock`) or otherwise (→ `unauthenticated`), then emit `AuthRateLimited(remainingSeconds: kLockoutDurationsSeconds[_escalationLevel], escalationLevel: _escalationLevel)` — do NOT emit `AuthError` for this threshold-triggering attempt; for the first N < kMaxFailedAttempts failures, emit `AuthError` as per the existing failed-attempt path (no new state introduced) (depends on T005, T006)
- [ ] T009 [US1] In `lib/blocs/auth_cubit.dart` `authenticate()` method: add guard at top — if current state is `AuthRateLimited`, return immediately without calling `LocalAuthService`; on `LocalAuthResult.success`, reset `_failedAttemptCount = 0` in `lib/blocs/auth_cubit.dart`
- [ ] T010 [US1] Add `AuthRateLimited` branch to `lib/screens/auth_screen.dart` `BlocBuilder`: render message "Too many failed attempts. Try again in X seconds." (where X = `state.remainingSeconds`) and a disabled authenticate button (depends on T007)

**Checkpoint**: T006 and T007 tests pass. Manual: deny 5 times → lockout screen visible; tapping button during lockout shows no prompt.

---

## Phase 4: User Story 2 — Live Countdown During Lockout (Priority: P2)

**Goal**: While in `AuthRateLimited`, the displayed remaining seconds decrement by 1 every second. At 0, the lockout message disappears and authentication is re-enabled.

**Independent Test**: Trigger lockout → observe countdown decrement each second → at 0, auth button becomes active and `_failedAttemptCount` is reset.

### Tests for User Story 2 ⚠️ Write these first — they must FAIL before implementation

- [ ] T011 [P] [US2] In `test/blocs/auth_cubit_rate_limit_test.dart`: write failing tests for — (a) after entering `AuthRateLimited`, advancing fake time by 1 s emits `AuthRateLimited(remainingSeconds: initial-1)`; (b) at `remainingSeconds == 0`, emits `AppLocked` when `_preLockoutContext == lifecycleLock` and `Unauthenticated` when `unauthenticated`; (c) `_lockoutTimer` is cancelled when cubit is closed
- [ ] T012 [P] [US2] In `test/widgets/auth_screen_rate_limit_test.dart`: write failing test — after pumping `AuthRateLimited(remainingSeconds: 10)` then `AuthRateLimited(remainingSeconds: 9)`, the displayed countdown updates to "9"

### Implementation for User Story 2

- [ ] T013 [US2] In `lib/blocs/auth_cubit.dart`: when emitting `AuthRateLimited`, record `_lockoutStartMs = DateTime.now().millisecondsSinceEpoch` and `_lockoutDurationSeconds = kLockoutDurationsSeconds[_escalationLevel]`; start `_lockoutTimer = Timer.periodic(const Duration(seconds: 1), _onLockoutTick)` (depends on T008, T011)
- [ ] T014 [US2] Implement `_onLockoutTick` in `lib/blocs/auth_cubit.dart`: compute `remainingSeconds = (_lockoutDurationSeconds! - ((now_ms - _lockoutStartMs!) / 1000)).ceil().clamp(0, _lockoutDurationSeconds!)`; emit `AuthRateLimited(remainingSeconds: remaining, escalationLevel: _escalationLevel)`; if `remaining == 0`, cancel timer, reset `_failedAttemptCount = 0`, and emit `AppLocked()` if `_preLockoutContext == _PreLockoutContext.lifecycleLock` else `Unauthenticated()`
- [ ] T015 [US2] Override `close()` in `lib/blocs/auth_cubit.dart`: cancel `_lockoutTimer` before calling `super.close()`
- [ ] T016 [US2] Update the `AuthRateLimited` branch in `lib/screens/auth_screen.dart`: bind `state.remainingSeconds` directly to the displayed countdown text so `BlocBuilder` rebuilds every second (depends on T012)

**Checkpoint**: T011 and T012 tests pass. Manual: lockout countdown decrements live; reaches 0 and auth button re-enables.

---

## Phase 5: User Story 3 — Exponential Backoff (Priority: P3)

**Goal**: Each successive lockout event uses a longer duration: 60 s → 120 s → 240 s → 900 s (cap). Escalation resets to 0 after a successful authentication.

**Independent Test**: Trigger lockout → wait → fail 5 more times → second lockout shows 120 s; repeat to verify 240 s, then 900 s cap; authenticate successfully → next lockout is 60 s again.

### Tests for User Story 3 ⚠️ Write these first — they must FAIL before implementation

- [ ] T017 [P] [US3] In `test/blocs/auth_cubit_rate_limit_test.dart`: write failing tests for — (a) first lockout starts with `remainingSeconds == 60`; (b) second lockout (after expiry) starts with `remainingSeconds == 120`; (c) third → 240 s; (d) fourth and beyond → capped at 900 s; (e) after successful auth, `_escalationLevel` resets so next lockout is 60 s

### Implementation for User Story 3

- [ ] T018 [US3] In `lib/blocs/auth_cubit.dart`: on the `kMaxFailedAttempts`-th failure, increment `_escalationLevel` (after reading the current level for duration, then clamped to `kLockoutDurationsSeconds.length - 1`) so the next lockout uses the next tier; use `kLockoutDurationsSeconds[_escalationLevel.clamp(0, kLockoutDurationsSeconds.length - 1)]` as the lockout duration when starting the timer (depends on T013, T017)
- [ ] T019 [US3] In `lib/blocs/auth_cubit.dart` `authenticate()` success path: reset `_escalationLevel = 0` alongside `_failedAttemptCount = 0`

**Checkpoint**: T017 tests pass. Manual: four consecutive lockout cycles produce 60 s, 120 s, 240 s, 900 s; success auth resets to 60 s.

---

## Phase 6: User Story 4 — Secure Persistence of Lock State (Priority: P4)

**Goal**: All lockout state (`failedAttemptCount`, `escalationLevel`, `lockoutStartMs`, `lockoutDurationSeconds`) is saved to `flutter_secure_storage` after every mutation. On cold start, any active lockout is restored with the correct remaining duration.

**Independent Test**: Trigger lockout → force-kill → relaunch → lockout screen shows correct remaining time (accounting for elapsed off-time); if lockout expired while closed, normal auth screen appears.

### Tests for User Story 4 ⚠️ Write these first — they must FAIL before implementation

- [ ] T020 [P] [US4] In `test/blocs/auth_cubit_rate_limit_test.dart` (using a mock `RateLimitStorageService`): write failing tests for — (a) `saveRecord` called with updated `failedAttemptCount` on each failed attempt; (b) `saveRecord` called with `lockoutStartMs` and `lockoutDurationSeconds` when lockout starts; (c) on cubit init with a stored active lockout record, cubit emits `AuthRateLimited` with correct `remainingSeconds`; (d) on cubit init with an expired stored record, cubit emits `Unauthenticated` and calls `clearRecord`; (e) `clearRecord` called on successful auth

### Implementation for User Story 4

- [ ] T021 [US4] In `lib/blocs/auth_cubit.dart`: call `await _storageService.saveRecord(RateLimitRecord(failedAttemptCount: _failedAttemptCount, escalationLevel: _escalationLevel, lockoutStartMs: null, lockoutDurationSeconds: null))` after each failed attempt increment; call `saveRecord` again with non-null `lockoutStartMs` and `lockoutDurationSeconds` when the lockout timer starts — this second save MUST occur after `_escalationLevel` has already been incremented (per T018 ordering), so the persisted `escalationLevel` represents the next lockout's tier (depends on T004, T020)
- [ ] T022 [US4] In `lib/blocs/auth_cubit.dart`: call `await _storageService.clearRecord()` on successful authentication and when the lockout timer reaches 0
- [ ] T023 [US4] In `lib/blocs/auth_cubit.dart` constructor or early in `authenticate()`: call `await _storageService.loadRecord()`; if record is non-null and `lockoutStartMs != null`, compute `remainingSeconds`; if `remainingSeconds > 0`, restore `_failedAttemptCount`, `_escalationLevel`, and emit `AuthRateLimited(remainingSeconds: remaining, escalationLevel: record.escalationLevel)` then start the countdown timer; if expired, emit `Unauthenticated` and `clearRecord` (defaults `_preLockoutContext` to `unauthenticated` per data-model.md cold-start rule)

**Checkpoint**: T020 tests pass. Manual: force-kill during lockout → relaunch → remaining time is correct; expired lockout on relaunch → normal screen.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T024 [P] Run `flutter analyze` from repo root and resolve all warnings and hints across modified files (`auth_state.dart`, `auth_cubit.dart`, `auth_screen.dart`, `rate_limit_storage_service.dart`)
- [ ] T025 Run `flutter test test/blocs/auth_cubit_rate_limit_test.dart test/widgets/auth_screen_rate_limit_test.dart` and confirm all tests pass with 0 failures
- [ ] T026 [P] Execute the manual verification scenarios from `specs/001-failed-attempts-limiter/quickstart.md` on a physical or emulated device: lockout trigger, countdown, persistence (force-kill), exponential backoff sequence, and reset-on-success; also verify SC-001: completing 5 failed attempts and reaching the lockout screen takes under 60 seconds of interaction time

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Requires Phase 1 complete — **BLOCKS all user story phases**
- **US1 (Phase 3)**: Requires Phase 2 complete
- **US2 (Phase 4)**: Requires Phase 3 complete (countdown extends the lockout state introduced in US1)
- **US3 (Phase 5)**: Requires Phase 3 complete; can run in parallel with Phase 4
- **US4 (Phase 6)**: Requires Phase 5 complete (needs escalation fully implemented before persisting it)
- **Polish (Phase 7)**: Requires Phases 3–6 complete

### User Story Dependencies

```
Phase 1 (Setup)
  └── Phase 2 (Foundational)
        ├── Phase 3 (US1 — Lockout core)
        │     ├── Phase 4 (US2 — Countdown)    ─┐
        │     └── Phase 5 (US3 — Backoff)      ─┤── Phase 6 (US4 — Persistence)
        │                                         └── Phase 7 (Polish)
```

### Parallel Opportunities

- T003 and T004 (Foundational): different files → parallel
- T006 and T007 (US1 tests): different files → parallel
- T011 and T012 (US2 tests): different files → parallel
- Phase 4 and Phase 5 (US2 and US3): can proceed simultaneously after Phase 3 is complete if two developers are available
- T024 and T026 (Polish): independent → parallel

---

## Parallel Example: User Story 1

```
# Write both test files simultaneously:
T006 → test/blocs/auth_cubit_rate_limit_test.dart
T007 → test/widgets/auth_screen_rate_limit_test.dart

# Then implement sequentially (same file):
T008 → failure tracking + AuthRateLimited emit
T009 → lockout guard + success reset
T010 → AuthScreen UI branch
```

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Foundational) — CRITICAL blocker
3. Complete Phase 3 (US1) — write tests, implement, verify
4. **STOP and VALIDATE**: 5 failures → lockout screen; blocked attempts; no biometric prompt shown
5. Demo to stakeholders if desired

### Incremental Delivery

1. Setup + Foundational → project compiles cleanly
2. US1 → lockout enforcement working (security baseline met)
3. US2 → live countdown UX working
4. US3 → exponential backoff working
5. US4 → persistence bypass-resistance working
6. Polish → clean, tested, verified

Each phase adds observable value and is independently verifiable before moving on.

---

## Notes

- `[P]` tasks touch different files and have no incomplete dependencies — safe to parallelize
- `[Story]` label maps each task to the user story it delivers
- Test tasks are ordered before implementation within each story (TDD per Constitution Principle V)
- `flutter_secure_storage` requires Android API 23+; setup task T002 handles this
- `_preLockoutContext` is not persisted — cold-start always defaults to `unauthenticated` (see data-model.md §Pre-Lockout Context)
- The `RateLimitStorageService` constructor injection (not static methods) enables mocking in T020 tests
