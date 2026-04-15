# Research: Failed Attempts Limiter

**Feature**: `001-failed-attempts-limiter`
**Date**: 2026-04-14

---

## Decision 1: Secure Storage Library

**Decision**: `flutter_secure_storage ^9.x`

**Rationale**: The de-facto standard for encrypted key-value storage in Flutter.
Uses Android Keystore (AES-256 GCM) on Android and iOS Keychain on iOS — both
hardware-backed. Supports Windows via DPAPI (already a target based on modified
`generated_plugin_registrant` files in the repo). The API is simple (read/write
string values by key), perfectly suited for the four scalar values we need to
persist (`lockout_start_ms`, `lockout_duration_s`, `escalation_level`,
`failed_count`).

**Alternatives considered**:

- `shared_preferences`: No encryption — rules it out for security-sensitive lockout data.
- `sqflite` / `drift`: Relational overhead unjustified for four scalar fields.
- `hive` with `hive_flutter`: Supports encryption but requires key management
  (storing the key securely itself requires Keystore, adding a layer we'd have to
  implement manually). `flutter_secure_storage` handles this natively.

---

## Decision 2: Countdown Timer Mechanism

**Decision**: `Timer.periodic` inside `AuthCubit` with `Stream`-based tick events.

**Rationale**: `AuthCubit` already owns all auth state; placing the timer there
keeps the countdown lifecycle tied to the cubit (cancelled on `close()`). Using
`Timer.periodic(Duration(seconds: 1), ...)` to decrement remaining seconds and
emit a new `AuthRateLimited` state on each tick is the simplest approach that
satisfies the "update every second" requirement. The cubit emits a new
`AuthRateLimited(remainingSeconds: N)` each tick; the `BlocBuilder` in
`AuthScreen` rebuilds the countdown display reactively.

**Alternatives considered**:

- `Stream.periodic` + `StreamSubscription`: Slightly more idiomatic Dart but no
  meaningful advantage over `Timer.periodic` when the timer is cubit-managed.
- UI-layer `StatefulWidget` with `AnimationController`: Moves timing logic into
  the view layer, violating the Cubit pattern and making unit testing harder.
- `rxdart` `TimerStream`: External dependency with no benefit over stdlib `Timer`.

---

## Decision 3: Exponential Backoff Schedule

**Decision**: Pre-computed constant list `kLockoutDurationsSeconds = [60, 120, 240, 900]`.

**Rationale**: The spec defines exactly four levels (60 s, 120 s, 240 s, capped at
900 s). A fixed list indexed by `escalationLevel` (clamped to `list.length - 1`)
is O(1) lookup, requires no computation at runtime, and is trivially testable.
`escalationLevel` is stored and incremented on each lockout event; a successful
auth resets it to 0.

**Alternatives considered**:

- `duration = 60 * 2^level` formula: Works but requires separate cap enforcement;
  the list is more readable and makes the schedule explicit in code.
- Configurable via `dart_define` or remote config: Over-engineering for a
  single-user mobile app; the spec explicitly defers configurability.

---

## Decision 4: State Isolation — `AuthRateLimited` vs `AppLocked`

**Decision**: `AuthRateLimited` is a sibling state to `AppLocked`; they MUST NOT
be nested or merged. When the `AuthRateLimited` timer expires, the cubit checks
the _pre-lockout context_ (a stored enum flag: `_preLockoutContext`) to determine
whether to emit `AppLocked` or `Unauthenticated` as the successor state.

**Rationale**: The clarification session established that if a user was in
`AppLocked` when they exhausted attempts, returning to `AppLocked` (not
`Unauthenticated`) after the timer expires is required. The cubit must therefore
remember why the user was on the auth screen before the rate-limit kicked in.
A single `_PreLockoutContext` private enum (`lifecycleLock`, `unauthenticated`)
stored as a cubit field is sufficient; it's set whenever `authenticate()` is
called and the cubit is in `AppLocked` vs `Unauthenticated`.

**Alternatives considered**:

- Inspecting `_backgroundTime` to re-derive context: Fragile; `_backgroundTime`
  gets cleared on various paths.
- Storing prior state type: Same information, slightly more coupling to state class
  hierarchy than a dedicated enum.

---

## Decision 5: `RateLimitStorageService` Abstraction

**Decision**: Introduce a thin `RateLimitStorageService` class that wraps
`flutter_secure_storage` with typed read/write methods. `AuthCubit` receives it
via constructor injection (dependency inversion).

**Rationale**: Constitution Principle II mandates platform abstraction. Injecting
the service makes it mockable for unit tests (Principle V), consistent with how
`LocalAuthService` is structured. The service exposes:

- `Future<RateLimitRecord?> loadRecord()`
- `Future<void> saveRecord(RateLimitRecord record)`
- `Future<void> clearRecord()`

**Alternatives considered**:

- Direct `flutter_secure_storage` calls inside `AuthCubit`: Violates platform
  abstraction and makes unit testing require real storage.
- Static methods (mirroring `LocalAuthService`): `LocalAuthService` is static for
  historical reasons; new code SHOULD use instance injection for testability.
