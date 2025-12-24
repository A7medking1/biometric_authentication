import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/auth_cubit.dart';
import '../blocs/auth_state.dart';
import '../screens/auth_screen.dart';

/// Widget that wraps protected content and shows auth screen when unauthenticated
class AuthGate extends StatefulWidget {
  final Widget child;
  final bool checkOnInit;

  const AuthGate({super.key, required this.child, this.checkOnInit = true});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    if (widget.checkOnInit) {
      // Check device capabilities on init
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AuthCubit>().checkDeviceCapabilities();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        // Show protected content only when authenticated
        if (state is Authenticated) {
          return widget.child;
        }

        // Show authentication screen for all other states (including AppLocked)
        return const AuthScreen();
      },
    );
  }
}
