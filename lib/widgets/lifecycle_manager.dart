import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/auth_cubit.dart';

/// Widget that monitors app lifecycle and triggers authentication on resume
class LifecycleManager extends StatefulWidget {
  final Widget child;

  const LifecycleManager({super.key, required this.child});

  @override
  State<LifecycleManager> createState() => _LifecycleManagerState();
}

class _LifecycleManagerState extends State<LifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Register as lifecycle observer
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Unregister observer when widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final authCubit = context.read<AuthCubit>();

    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground
        authCubit.handleAppResumed();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // App went to background or became inactive
        authCubit.handleAppPaused();
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is being terminated or hidden
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Simply return the child - this widget is transparent
    return widget.child;
  }
}
