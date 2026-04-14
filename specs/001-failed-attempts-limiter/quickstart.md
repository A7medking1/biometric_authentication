# Quickstart: Failed Attempts Limiter

**Feature**: `001-failed-attempts-limiter`
**Date**: 2026-04-14

---

## Prerequisites

1. Flutter SDK ≥ 3.9 installed and on PATH
2. Android emulator or physical device (API 23+) for biometric hardware simulation,
   OR iOS simulator (iOS 15+)
3. `flutter pub get` completed (will need `flutter_secure_storage` added to
   `pubspec.yaml` — see step 1 below)

---

## Setup

### 1. Add `flutter_secure_storage`

```yaml
# pubspec.yaml — under dependencies:
flutter_secure_storage: ^9.2.2
```

```bash
flutter pub get
```

### 2. Android minimum SDK (required by `flutter_secure_storage`)

In `android/app/build.gradle.kts`, ensure:

```kotlin
defaultConfig {
    minSdk = 23   // was 21; flutter_secure_storage requires 23
}
```

### 3. Run the app

```bash
flutter run -d android   # or -d ios
```

---

## Verify the Feature Manually

### Trigger lockout

1. Launch the app on a device/emulator with biometrics enrolled.
2. On the authentication screen, deny the biometric prompt 5 times consecutively.
3. **Expected**: The screen transitions to a lockout view showing
   "Too many failed attempts. Try again in 60 seconds." with a live countdown.

### Verify countdown

4. Watch the countdown decrement every second.
5. **Expected**: Timer reaches 0, auth button re-enables, counter resets.

### Verify persistence

6. While in lockout, force-kill the app (swipe away from recents).
7. Relaunch. **Expected**: The lockout screen reappears with the correct remaining
   time (accounting for elapsed time during closure).

### Verify exponential backoff

8. Wait for the first lockout to expire. Fail 5 more times.
9. **Expected**: Second lockout duration is 120 seconds (2 minutes).
10. Repeat: third lockout should be 240 seconds (4 minutes).
11. Any further lockouts should cap at 900 seconds (15 minutes).

### Verify reset on success

12. After a lockout expires, successfully authenticate.
13. Fail 5 times again. **Expected**: Lockout is 60 seconds (back to level 0).

---

## Run Tests

```bash
# All tests
flutter test

# Rate-limit cubit tests specifically
flutter test test/blocs/auth_cubit_rate_limit_test.dart

# Widget tests for locked state UI
flutter test test/widgets/auth_screen_rate_limit_test.dart
```

---

## Key Files

| File | Role |
|------|------|
| `lib/blocs/auth_state.dart` | Add `AuthRateLimited` state class |
| `lib/blocs/auth_cubit.dart` | Add rate-limit logic, timer, backoff |
| `lib/services/rate_limit_storage_service.dart` | New — secure storage wrapper |
| `lib/screens/auth_screen.dart` | Add `AuthRateLimited` branch to UI |
| `test/blocs/auth_cubit_rate_limit_test.dart` | New — cubit unit tests |
| `test/widgets/auth_screen_rate_limit_test.dart` | New — widget tests |
