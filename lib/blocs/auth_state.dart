import 'package:equatable/equatable.dart';

/// Base class for authentication states
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Initial state when app starts
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// State when authentication is in progress
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// State when user is authenticated
class Authenticated extends AuthState {
  final DateTime authenticatedAt;

  const Authenticated({required this.authenticatedAt});

  @override
  List<Object?> get props => [authenticatedAt];
}

/// State when user is not authenticated
class Unauthenticated extends AuthState {
  final String? message;

  const Unauthenticated({this.message});

  @override
  List<Object?> get props => [message];
}

/// State when authentication error occurs
class AuthError extends AuthState {
  final String message;
  final bool isRecoverable;

  /// Consecutive failed attempt count at the time this error was emitted.
  /// Included in props so successive failures produce distinct states and
  /// are not deduplicated by Equatable (FR-002).
  final int attemptCount;

  const AuthError({
    required this.message,
    this.isRecoverable = true,
    this.attemptCount = 0,
  });

  @override
  List<Object?> get props => [message, isRecoverable, attemptCount];
}

/// State when biometric is not available
class BiometricNotAvailable extends AuthState {
  final String message;

  const BiometricNotAvailable({
    this.message = 'Biometric authentication is not available on this device',
  });

  @override
  List<Object?> get props => [message];
}

/// State when biometric is not enrolled
class BiometricNotEnrolled extends AuthState {
  final String message;

  const BiometricNotEnrolled({
    this.message = 'No biometrics enrolled. Please set up in device settings',
  });

  @override
  List<Object?> get props => [message];
}

/// State when authentication is temporarily blocked due to too many failed attempts (FR-012)
class AuthRateLimited extends AuthState {
  /// Seconds remaining until the lockout expires (clamped to [0, lockoutDurationSeconds])
  final int remainingSeconds;

  /// The escalation level used for the current lockout (pre-increment; determines displayed duration)
  final int escalationLevel;

  const AuthRateLimited({
    required this.remainingSeconds,
    required this.escalationLevel,
  });

  @override
  List<Object?> get props => [remainingSeconds, escalationLevel];
}

/// State when app is locked due to lifecycle events (app resumed from background)
class AppLocked extends AuthState {
  final DateTime lockedAt;
  final String message;

  const AppLocked({
    required this.lockedAt,
    this.message = 'App locked. Please authenticate to continue',
  });

  @override
  List<Object?> get props => [lockedAt, message];
}
