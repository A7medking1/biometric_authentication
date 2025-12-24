import 'package:flutter_bloc/flutter_bloc.dart';

import '../local_auth_service.dart';
import 'auth_state.dart';

/// Cubit for managing authentication state
class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(const AuthInitial());

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
    emit(const Unauthenticated());
  }

  /// Reset to initial state
  void reset() {
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
}
