# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run app
flutter run                          # Default device
flutter run -d android               # Android
flutter run -d ios                   # iOS
flutter run --flavor development     # Development flavor
flutter run --flavor production      # Production flavor

# Test
flutter test                         # All tests
flutter test test/widget_test.dart   # Single file

# Lint & analysis
flutter analyze
dart fix --apply                     # Auto-fix lint issues

# Build
flutter build apk --release          # Android
flutter build ios --release          # iOS
```

## Architecture

State is managed via **flutter_bloc** (Cubit pattern). The core flow:

1. `main.dart` — Wraps the app in `BlocProvider<AuthCubit>` and `LifecycleManager`
2. `AuthGate` widget — Guards all content; shows `AuthScreen` when state is not `Authenticated`
3. `LifecycleManager` — `WidgetsBindingObserver` that calls `authCubit.handleAppPaused()` / `handleAppResumed()` on lifecycle changes, triggering auto-lock after a configurable timeout (default: 3 seconds)
4. `LocalAuthService` — Thin wrapper over the `local_auth` plugin; `authenticate()` returns `LocalAuthResult` (success, cancelled, error, notAvailable, notEnrolled)
5. `AuthCubit` — Orchestrates all state transitions; calls `LocalAuthService` and emits typed `AuthState` subclasses

### Auth State Machine

```
AuthInitial → AuthLoading → Authenticated
                          → Unauthenticated
                          → AuthError
                          → BiometricNotAvailable
                          → BiometricNotEnrolled
Authenticated → AppLocked (on resume after timeout)
```

`AppLocked` is distinct from `Unauthenticated` — it signals the user was previously authenticated but the app re-locked due to backgrounding.

## Platform Setup

**Android** — `USE_BIOMETRIC` permission declared in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml). Two build flavors defined in [android/app/build.gradle.kts](android/app/build.gradle.kts): `development` (appId suffix `.dev`) and `production`.

**iOS** — `NSFaceIDUsageDescription` declared in [ios/Runner/Info.plist](ios/Runner/Info.plist). Minimum deployment target: iOS 10.0.

## Key Files

| File | Role |
|------|------|
| [lib/main.dart](lib/main.dart) | Entry point, provider setup, lifecycle wiring |
| [lib/local_auth_service.dart](lib/local_auth_service.dart) | Biometric plugin abstraction |
| [lib/blocs/auth_cubit.dart](lib/blocs/auth_cubit.dart) | All auth business logic |
| [lib/blocs/auth_state.dart](lib/blocs/auth_state.dart) | Typed state definitions |
| [lib/widgets/auth_gate.dart](lib/widgets/auth_gate.dart) | Route guard |
| [lib/widgets/lifecycle_manager.dart](lib/widgets/lifecycle_manager.dart) | App lifecycle observer |
| [lib/screens/auth_screen.dart](lib/screens/auth_screen.dart) | Auth UI |

## Recent Changes
- 001-failed-attempts-limiter: Added Dart 3.9+ / Flutter 3.x (SDK constraint `^3.9.0`) + flutter_bloc ^8.1.6, equatable ^2.0.5, local_auth ^3.0.0,
- 001-failed-attempts-limiter: Added [if applicable, e.g., PostgreSQL, CoreData, files or N/A]

## Active Technologies
- Dart 3.9+ / Flutter 3.x (SDK constraint `^3.9.0`) + flutter_bloc ^8.1.6, equatable ^2.0.5, local_auth ^3.0.0, (001-failed-attempts-limiter)
- flutter_secure_storage (Android Keystore AES-256 GCM / iOS Keychain / (001-failed-attempts-limiter)
