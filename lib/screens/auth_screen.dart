import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/auth_cubit.dart';
import '../blocs/auth_state.dart';

/// Authentication screen with modern UI
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          // Auto-retry for certain states
          if (state is BiometricNotEnrolled || state is BiometricNotAvailable) {
            // Show snackbar for info
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state is BiometricNotEnrolled
                      ? 'Please set up biometrics in device settings'
                      : 'Biometric authentication not available',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
        builder: (context, state) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // App logo or icon
                      Icon(
                        state is AppLocked ? Icons.lock : Icons.fingerprint,
                        size: 120,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Text(
                        'Secure Authentication',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      // Subtitle based on state
                      Text(
                        _getSubtitle(state),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),

                      // Loading indicator or error message
                      if (state is AuthLoading)
                        const CircularProgressIndicator()
                      else if (state is AuthError)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.message,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (state is BiometricNotAvailable)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.message,
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (state is BiometricNotEnrolled)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.message,
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 32),

                      // Authenticate button
                      if (state is! AuthLoading)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _handleAuthenticate(context, state),
                            icon: Icon(_getButtonIcon(state), size: 24),
                            label: Text(
                              _getButtonText(state),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),

                      // Device credentials fallback option
                      if (state is BiometricNotEnrolled ||
                          (state is AuthError && state.isRecoverable))
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: TextButton.icon(
                            onPressed: () =>
                                context.read<AuthCubit>().authenticate(
                                  reason:
                                      'Authenticate with device credentials',
                                  biometricOnly: false,
                                ),
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Use Device PIN/Pattern'),
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleAuthenticate(BuildContext context, AuthState state) {
    if (state is AuthError && state.isRecoverable) {
      context.read<AuthCubit>().retry();
    } else if (state is BiometricNotAvailable) {
      // Try with device credentials
      context.read<AuthCubit>().authenticate(
        reason: 'Authenticate with device credentials',
        biometricOnly: false,
      );
    } else {
      context.read<AuthCubit>().authenticate();
    }
  }

  String _getSubtitle(AuthState state) {
    if (state is AuthLoading) {
      return 'Authenticating...';
    } else if (state is AppLocked) {
      return state.message;
    } else if (state is AuthError) {
      return 'Please try again';
    } else if (state is BiometricNotAvailable) {
      return 'Use device PIN or pattern to continue';
    } else if (state is BiometricNotEnrolled) {
      return 'Set up biometrics or use device credentials';
    } else if (state is Unauthenticated) {
      return state.message ?? 'Please authenticate to continue';
    }
    return 'Please authenticate to access the app';
  }

  String _getButtonText(AuthState state) {
    if (state is AuthError) {
      return 'Retry';
    } else if (state is BiometricNotAvailable) {
      return 'Authenticate with PIN';
    }
    return 'Authenticate';
  }

  IconData _getButtonIcon(AuthState state) {
    if (state is AuthError) {
      return Icons.refresh;
    } else if (state is BiometricNotAvailable) {
      return Icons.lock;
    }
    return Icons.fingerprint;
  }
}
