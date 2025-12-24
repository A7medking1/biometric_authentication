import 'package:flutter_bloc/flutter_bloc.dart';

import '../local_auth_service.dart';
import 'auth_state.dart';

/// Cubit for managing authentication state
class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(const AuthInitial());

  /// Time when app went to background
  DateTime? _backgroundTime;

  /// Duration threshold for requiring re-authentication (0 = always lock on resume)
  Duration lockTimeout = const Duration(seconds: 3);

  /// Check if user is currently authenticated
  bool get isAuthenticated => state is Authenticated;

  /// Authenticate user with biometrics
  Future<void> authenticate({
    String reason = 'Please authenticate to continue',
    bool biometricOnly = false,
  }) async {
    emit(const AuthLoading());

    try {
      final result = await LocalAuthService.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
      );

      switch (result) {
        case AuthResult.success:
          _backgroundTime = null; // Clear background time to prevent immediate re-lock
          emit(Authenticated(authenticatedAt: DateTime.now()));
          break;
        case AuthResult.cancelled:
          emit(const Unauthenticated(message: 'Authentication cancelled'));
          break;
        case AuthResult.failed:
          emit(
            const AuthError(
              message: 'Authentication failed. Please try again',
              isRecoverable: true,
            ),
          );
          break;
        case AuthResult.notAvailable:
          emit(const BiometricNotAvailable());
          break;
        case AuthResult.notEnrolled:
          emit(const BiometricNotEnrolled());
          break;
        case AuthResult.error:
          emit(
            const AuthError(
              message: 'An error occurred during authentication',
              isRecoverable: true,
            ),
          );
          break;
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

  /// Logout user
  void logout() {
    _backgroundTime = null; // Clear background time
    emit(const Unauthenticated());
  }

  /// Reset to initial state
  void reset() {
    _backgroundTime = null; // Clear background time
    emit(const AuthInitial());
  }

  /// Check device capabilities
  Future<void> checkDeviceCapabilities() async {
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

      // Device is capable, go back to unauthenticated state
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

  /// Handle app resumed event
  void handleAppResumed() {
    if (_shouldRequireAuth()) {
      lockApp();
    }
  }

  /// Check if re-authentication is required based on timeout
  bool _shouldRequireAuth() {
    // Only require auth if currently authenticated
    if (state is! Authenticated) {
      return false;
    }

    // If no background time recorded, don't require auth
    if (_backgroundTime == null) {
      return false;
    }

    // If timeout is 0, always require auth on resume
    if (lockTimeout.inSeconds == 0) {
      return true;
    }

    // Check if background duration exceeds timeout
    final backgroundDuration = DateTime.now().difference(_backgroundTime!);
    return backgroundDuration >= lockTimeout;
  }
}
