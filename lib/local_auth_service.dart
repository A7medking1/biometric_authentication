import 'package:local_auth/local_auth.dart';

/// Result of an authentication attempt
enum AuthResult { success, cancelled, failed, notAvailable, notEnrolled, error }

/// Custom exception for authentication errors
class AuthException implements Exception {
  final String message;
  final AuthResult result;

  AuthException(this.message, this.result);

  @override
  String toString() => 'AuthException: $message';
}

/// Service for handling local biometric authentication
class LocalAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if the device supports biometric authentication
  static Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  /// Check if biometrics can be used (device supports AND user has enrolled)
  static Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Get list of available biometric types
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Authenticate using biometrics only
  static Future<AuthResult> authenticateWithBiometrics({
    String localizedReason = 'Please authenticate to continue',
  }) async {
    try {
      // Check if device supports biometrics
      final isSupported = await isDeviceSupported();
      if (!isSupported) {
        return AuthResult.notAvailable;
      }

      // Check if biometrics are enrolled
      final canCheck = await canCheckBiometrics();
      if (!canCheck) {
        return AuthResult.notEnrolled;
      }

      // Attempt authentication
      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        authMessages: const [],
      );

      return authenticated ? AuthResult.success : AuthResult.failed;
    } on Exception catch (e) {
      // Handle specific error codes
      if (e.toString().contains('NotAvailable') ||
          e.toString().contains('notAvailable')) {
        return AuthResult.notAvailable;
      } else if (e.toString().contains('NotEnrolled') ||
          e.toString().contains('notEnrolled')) {
        return AuthResult.notEnrolled;
      } else if (e.toString().contains('UserCanceled') ||
          e.toString().contains('CANCELED')) {
        return AuthResult.cancelled;
      }
      return AuthResult.error;
    }
  }

  /// Authenticate using biometrics with device credentials as fallback
  static Future<AuthResult> authenticate({
    String localizedReason = 'Please authenticate to continue',
    bool biometricOnly = false,
  }) async {
    try {
      // Check if device supports authentication
      final isSupported = await isDeviceSupported();
      if (!isSupported) {
        throw AuthException(
          'This device does not support biometric authentication',
          AuthResult.notAvailable,
        );
      }

      // Attempt authentication
      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        authMessages: const [],
      );

      return authenticated ? AuthResult.success : AuthResult.failed;
    } on AuthException {
      rethrow;
    } on Exception catch (e) {
      // Handle specific error codes
      if (e.toString().contains('NotAvailable') ||
          e.toString().contains('notAvailable')) {
        return AuthResult.notAvailable;
      } else if (e.toString().contains('NotEnrolled') ||
          e.toString().contains('notEnrolled')) {
        return AuthResult.notEnrolled;
      } else if (e.toString().contains('UserCanceled') ||
          e.toString().contains('CANCELED')) {
        return AuthResult.cancelled;
      }
      return AuthResult.error;
    }
  }

  /// Stop authentication if it's in progress
  static Future<bool> stopAuthentication() async {
    try {
      return await _auth.stopAuthentication();
    } catch (e) {
      return false;
    }
  }

  /// Get a user-friendly message for an auth result
  static String getResultMessage(AuthResult result) {
    switch (result) {
      case AuthResult.success:
        return 'Authentication successful';
      case AuthResult.cancelled:
        return 'Authentication cancelled';
      case AuthResult.failed:
        return 'Authentication failed';
      case AuthResult.notAvailable:
        return 'Biometric authentication is not available on this device';
      case AuthResult.notEnrolled:
        return 'No biometrics enrolled. Please set up biometrics in your device settings';
      case AuthResult.error:
        return 'An error occurred during authentication';
    }
  }
}
