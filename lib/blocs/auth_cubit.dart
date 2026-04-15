import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../local_auth_service.dart';
import '../services/rate_limit_storage_service.dart';
import 'auth_state.dart';

/// Maximum consecutive failed attempts before lockout (FR-002)
const int kMaxFailedAttempts = 5;

/// Backoff schedule indexed by escalation level (FR-006).
/// level 0 → 60 s, level 1 → 120 s, level 2 → 240 s, level 3+ → 900 s (cap)
const List<int> kLockoutDurationsSeconds = [60, 120, 240, 900];

/// Injectable authentication function — defaults to [LocalAuthService.authenticate].
/// Parameter name is [reason] (mapped to [LocalAuthService]'s `localizedReason`).
/// Declare it in tests to return controlled [AuthResult] values (Constitution Principle V).
typedef AuthenticateFunction =
    Future<AuthResult> Function({
      String reason,
      bool biometricOnly,
    });

/// Default implementation that delegates to [LocalAuthService.authenticate].
Future<AuthResult> _defaultAuthenticate({
  String reason = 'Please authenticate to continue',
  bool biometricOnly = false,
}) => LocalAuthService.authenticate(
  localizedReason: reason,
  biometricOnly: biometricOnly,
);

/// Which state preceded the current [AuthRateLimited] lockout.
/// Determines the successor state when the lockout timer expires (FR-013).
enum _PreLockoutContext { lifecycleLock, unauthenticated }

/// Orchestrates all authentication state transitions (Constitution Principle III).
///
/// Rate-limit additions (feature 001):
/// - Tracks consecutive failures; locks out on [kMaxFailedAttempts] (FR-001, FR-002)
/// - Runs a [Timer.periodic] countdown; emits new [AuthRateLimited] each tick (FR-003)
/// - Exponential-backoff schedule via [kLockoutDurationsSeconds] (FR-006)
/// - Persists all lockout state to [RateLimitStorageService] (FR-008)
/// - Restores active lockout on cold start (FR-009)
class AuthCubit extends Cubit<AuthState> {
  final RateLimitStorageService _storageService;
  final AuthenticateFunction _authenticateFn;

  /// Time when app went to background (for lifecycle auto-lock)
  DateTime? _backgroundTime;

  /// Duration threshold for requiring re-authentication (default: 3 s)
  Duration lockTimeout = const Duration(seconds: 3);

  // ── Rate-limit state ──────────────────────────────────────────────────────

  int _failedAttemptCount = 0;

  /// Next lockout's escalation level (post-increment). Reset to 0 on success.
  int _escalationLevel = 0;

  /// Which state preceded the active lockout — determines successor on expiry.
  _PreLockoutContext _preLockoutContext = _PreLockoutContext.unauthenticated;

  /// Periodic timer that emits countdown ticks during lockout.
  Timer? _lockoutTimer;

  /// Absolute start timestamp of the active lockout (ms since epoch).
  int? _lockoutStartMs;

  /// Total duration of the active lockout in seconds.
  int? _lockoutDurationSeconds;

  // ─────────────────────────────────────────────────────────────────────────

  AuthCubit({
    required RateLimitStorageService storageService,
    AuthenticateFunction? authenticate,
  }) : _storageService = storageService,
       _authenticateFn = authenticate ?? _defaultAuthenticate,
       super(const AuthInitial());

  bool get isAuthenticated => state is Authenticated;

  /// Authenticate with biometrics.
  ///
  /// Returns immediately without calling the biometric API if currently in
  /// [AuthRateLimited] (lockout guard — FR-012).
  Future<void> authenticate({
    String reason = 'Please authenticate to continue',
    bool biometricOnly = false,
  }) async {
    // Lockout guard (FR-012)
    if (state is AuthRateLimited) return;

    // Capture context before emitting AuthLoading
    final bool wasAppLocked = state is AppLocked;
    final DateTime? originalLockedAt = wasAppLocked
        ? (state as AppLocked).lockedAt
        : null;

    emit(const AuthLoading());

    try {
      final result = await _authenticateFn(
        reason: reason,
        biometricOnly: biometricOnly,
      );

      switch (result) {
        case AuthResult.success:
          // FR-004, FR-007: reset both counter and escalation on success
          _backgroundTime = null;
          _failedAttemptCount = 0;
          _escalationLevel = 0;
          await _storageService.clearRecord(); // T022
          emit(Authenticated(authenticatedAt: DateTime.now()));

        case AuthResult.cancelled:
          // FR-010: cancelled must NOT increment the counter
          emit(const Unauthenticated(message: 'Authentication cancelled'));

        case AuthResult.failed:
          _failedAttemptCount++;
          if (_failedAttemptCount >= kMaxFailedAttempts) {
            // FR-002: 5th failure → AuthRateLimited directly (no intermediate AuthError)
            _preLockoutContext = wasAppLocked
                ? _PreLockoutContext.lifecycleLock
                : _PreLockoutContext.unauthenticated;
            await _startLockout();
          } else {
            // Failures 1–4: emit AuthError and persist updated count (T021 partial)
            await _storageService.saveRecord(
              RateLimitRecord(
                failedAttemptCount: _failedAttemptCount,
                escalationLevel: _escalationLevel,
              ),
            );
            emit(
              AuthError(
                message: 'Authentication failed. Please try again',
                isRecoverable: true,
                attemptCount: _failedAttemptCount,
              ),
            );
          }

        case AuthResult.notAvailable:
          // FR-011: hardware events must NOT change counter; preserve AppLocked if applicable
          if (wasAppLocked) {
            emit(AppLocked(lockedAt: originalLockedAt ?? DateTime.now()));
          } else {
            emit(const BiometricNotAvailable());
          }

        case AuthResult.notEnrolled:
          // FR-011: same rule as notAvailable
          if (wasAppLocked) {
            emit(AppLocked(lockedAt: originalLockedAt ?? DateTime.now()));
          } else {
            emit(const BiometricNotEnrolled());
          }

        case AuthResult.error:
          emit(
            const AuthError(
              message: 'An error occurred during authentication',
              isRecoverable: true,
            ),
          );
      }
    } on AuthException catch (e) {
      emit(AuthError(message: e.message, isRecoverable: false));
    } catch (e) {
      emit(
        AuthError(
          message: 'Unexpected error: ${e.toString()}',
          isRecoverable: false,
        ),
      );
    }
  }

  /// Initiates a new lockout: records start time, increments escalation,
  /// persists to storage, emits [AuthRateLimited], and starts the countdown timer.
  Future<void> _startLockout() async {
    final int duration = kLockoutDurationsSeconds[_escalationLevel];
    final int currentLevel = _escalationLevel; // pre-increment (for display)

    _lockoutStartMs = clock.now().millisecondsSinceEpoch;
    _lockoutDurationSeconds = duration;

    // FR-006: increment escalation for next lockout, clamped at max tier
    _escalationLevel = (_escalationLevel + 1).clamp(
      0,
      kLockoutDurationsSeconds.length - 1,
    );

    // T021: save AFTER escalation increment so stored level = next lockout's tier
    await _storageService.saveRecord(
      RateLimitRecord(
        failedAttemptCount: _failedAttemptCount,
        escalationLevel: _escalationLevel,
        lockoutStartMs: _lockoutStartMs,
        lockoutDurationSeconds: _lockoutDurationSeconds,
      ),
    );

    emit(
      AuthRateLimited(
        remainingSeconds: duration,
        escalationLevel:
            currentLevel, // current lockout's level (pre-increment)
      ),
    );

    _startCountdownTimer();
  }

  /// Starts (or restarts) the periodic countdown timer.
  void _startCountdownTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), _onLockoutTick);
  }

  /// Called every second while in [AuthRateLimited].
  ///
  /// Computes remaining time from the absolute start timestamp so that
  /// missed ticks in background do not accumulate error (FR-003, FR-014).
  void _onLockoutTick(Timer timer) {
    if (_lockoutStartMs == null || _lockoutDurationSeconds == null) {
      timer.cancel();
      return;
    }

    final nowMs = clock.now().millisecondsSinceEpoch;
    final elapsedSeconds = (nowMs - _lockoutStartMs!) / 1000;
    final remaining = (_lockoutDurationSeconds! - elapsedSeconds).ceil().clamp(
      0,
      _lockoutDurationSeconds!,
    );

    if (remaining <= 0) {
      // Lockout expired
      timer.cancel();
      _lockoutTimer = null;
      _failedAttemptCount = 0; // FR-005
      _lockoutStartMs = null;
      _lockoutDurationSeconds = null;
      _storageService.clearRecord(); // T022 (fire-and-forget)

      // FR-013: successor state depends on pre-lockout context
      if (_preLockoutContext == _PreLockoutContext.lifecycleLock) {
        emit(AppLocked(lockedAt: clock.now()));
      } else {
        emit(const Unauthenticated());
      }
    } else {
      final currentState = state;
      emit(
        AuthRateLimited(
          remainingSeconds: remaining,
          escalationLevel: currentState is AuthRateLimited
              ? currentState.escalationLevel
              : 0,
        ),
      );
    }
  }

  /// Logout user
  void logout() {
    _backgroundTime = null;
    emit(const Unauthenticated());
  }

  /// Reset to initial state
  void reset() {
    _backgroundTime = null;
    emit(const AuthInitial());
  }

  /// Checks device capabilities and restores any active lockout from storage (FR-009).
  ///
  /// Called from [AuthGate.initState] — this is the cold-start entry point for T023.
  Future<void> checkDeviceCapabilities() async {
    // T023: check for persisted active lockout before device capability check
    try {
      final record = await _storageService.loadRecord();
      if (record != null &&
          record.lockoutStartMs != null &&
          record.lockoutDurationSeconds != null) {
        final nowMs = clock.now().millisecondsSinceEpoch;
        final elapsedSeconds = (nowMs - record.lockoutStartMs!) / 1000;
        final remaining = (record.lockoutDurationSeconds! - elapsedSeconds)
            .ceil()
            .clamp(0, record.lockoutDurationSeconds!);

        if (remaining > 0) {
          // Active lockout — restore state
          _failedAttemptCount = record.failedAttemptCount;
          _escalationLevel = record.escalationLevel; // next lockout's level
          _lockoutStartMs = record.lockoutStartMs;
          _lockoutDurationSeconds = record.lockoutDurationSeconds;
          // FR-009: cold-start always defaults to unauthenticated context
          _preLockoutContext = _PreLockoutContext.unauthenticated;

          emit(
            AuthRateLimited(
              remainingSeconds: remaining,
              // Derive current level from stored duration (avoids off-by-one with post-increment)
              escalationLevel: _levelFromDuration(
                record.lockoutDurationSeconds!,
              ),
            ),
          );
          _startCountdownTimer();
          return;
        } else {
          // Lockout expired while app was closed — clear storage, preserve escalation
          _failedAttemptCount = 0;
          _escalationLevel = record.escalationLevel;
          await _storageService.clearRecord();
          // Fall through to normal capability check
        }
      }
    } catch (_) {
      // Storage failure — proceed with normal capability check
    }

    emit(const AuthLoading());
    try {
      final isSupported = await LocalAuthService.isDeviceSupported();
      if (!isSupported) {
        emit(const BiometricNotAvailable());
        return;
      }
      final canCheck = await LocalAuthService.canCheckBiometrics();
      if (!canCheck) {
        emit(const BiometricNotEnrolled());
        return;
      }
      emit(const Unauthenticated());
    } catch (e) {
      emit(
        AuthError(
          message: 'Failed to check device capabilities: ${e.toString()}',
          isRecoverable: false,
        ),
      );
    }
  }

  /// Returns the escalation level whose duration matches [durationSeconds],
  /// falling back to the last tier if not found.
  int _levelFromDuration(int durationSeconds) {
    final index = kLockoutDurationsSeconds.indexOf(durationSeconds);
    return index >= 0 ? index : kLockoutDurationsSeconds.length - 1;
  }

  /// Retry authentication after error
  Future<void> retry({
    String reason = 'Please authenticate to continue',
  }) async {
    await authenticate(reason: reason);
  }

  /// Lock the app, requiring re-authentication
  void lockApp() {
    if (state is Authenticated) {
      emit(AppLocked(lockedAt: DateTime.now()));
    }
  }

  /// Handle app paused/inactive event
  void handleAppPaused() {
    _backgroundTime = DateTime.now();
  }

  /// Handle app resumed event.
  ///
  /// FR-015: [_shouldRequireAuth] returns false for all non-[Authenticated] states,
  /// including [AuthRateLimited], so no additional guard is needed here.
  void handleAppResumed() {
    if (_shouldRequireAuth()) {
      lockApp();
    }
  }

  /// Returns true only when the app is [Authenticated] and the background timeout
  /// has elapsed. Never true during [AuthRateLimited] (satisfies FR-015).
  bool _shouldRequireAuth() {
    if (state is! Authenticated) return false;
    if (_backgroundTime == null) return false;
    if (lockTimeout.inSeconds == 0) return true;
    return DateTime.now().difference(_backgroundTime!) >= lockTimeout;
  }

  @override
  Future<void> close() {
    _lockoutTimer?.cancel(); // T015
    return super.close();
  }
}
