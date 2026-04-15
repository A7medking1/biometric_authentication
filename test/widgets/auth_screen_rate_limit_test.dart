import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:for_learning/blocs/auth_cubit.dart';
import 'package:for_learning/blocs/auth_state.dart';
import 'package:for_learning/screens/auth_screen.dart';
import 'package:for_learning/services/rate_limit_storage_service.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockRateLimitStorageService extends Mock
    implements RateLimitStorageService {}

// ── Helpers ────────────────────────────────────────────────────────────────

MockRateLimitStorageService _mockStorage() {
  final m = MockRateLimitStorageService();
  when(() => m.loadRecord()).thenAnswer((_) async => null);
  when(() => m.saveRecord(any())).thenAnswer((_) async {});
  when(() => m.clearRecord()).thenAnswer((_) async {});
  return m;
}

Widget _buildScreen(AuthCubit cubit) {
  return MaterialApp(
    home: BlocProvider<AuthCubit>.value(
      value: cubit,
      child: const AuthScreen(),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// T007 — US1: AuthRateLimited renders lockout message + disabled button
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RateLimitRecord(failedAttemptCount: 0, escalationLevel: 0),
    );
  });

  group('T007 — AuthRateLimited renders lockout UI', () {
    testWidgets(
        'shows lockout message containing remaining seconds and disabled button',
        (tester) async {
      final cubit = AuthCubit(
        storageService: _mockStorage(),
        authenticate: ({reason = '', biometricOnly = false}) async =>
            throw UnimplementedError(),
      );
      cubit.emit(
        const AuthRateLimited(remainingSeconds: 45, escalationLevel: 0),
      );

      await tester.pumpWidget(_buildScreen(cubit));

      // Should display remaining seconds
      expect(find.textContaining('45'), findsAtLeastNWidgets(1));

      // Auth button should be disabled (no onPressed handler)
      final elevatedButtons = tester.widgetList<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      for (final btn in elevatedButtons) {
        expect(btn.onPressed, isNull,
            reason: 'Authenticate button must be disabled during lockout');
      }

      await cubit.close();
    });

    testWidgets('shows lock icon during lockout', (tester) async {
      final cubit = AuthCubit(
        storageService: _mockStorage(),
        authenticate: ({reason = '', biometricOnly = false}) async =>
            throw UnimplementedError(),
      );
      cubit.emit(
        const AuthRateLimited(remainingSeconds: 30, escalationLevel: 0),
      );

      await tester.pumpWidget(_buildScreen(cubit));

      expect(find.byIcon(Icons.lock_clock), findsOneWidget);

      await cubit.close();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // T012 — US2: countdown display updates when state changes
  // ══════════════════════════════════════════════════════════════════════════

  group('T012 — Countdown display updates', () {
    testWidgets('pumping AuthRateLimited(10) then (9) updates displayed countdown',
        (tester) async {
      final cubit = AuthCubit(
        storageService: _mockStorage(),
        authenticate: ({reason = '', biometricOnly = false}) async =>
            throw UnimplementedError(),
      );
      cubit.emit(
        const AuthRateLimited(remainingSeconds: 10, escalationLevel: 0),
      );

      await tester.pumpWidget(_buildScreen(cubit));
      expect(find.textContaining('10'), findsAtLeastNWidgets(1));

      // Transition to 9 seconds
      cubit.emit(
        const AuthRateLimited(remainingSeconds: 9, escalationLevel: 0),
      );
      await tester.pump();

      expect(find.textContaining('9'), findsAtLeastNWidgets(1));

      await cubit.close();
    });

    testWidgets('button re-enables after lockout expires (Unauthenticated state)',
        (tester) async {
      final cubit = AuthCubit(
        storageService: _mockStorage(),
        authenticate: ({reason = '', biometricOnly = false}) async =>
            throw UnimplementedError(),
      );
      cubit.emit(
        const AuthRateLimited(remainingSeconds: 1, escalationLevel: 0),
      );

      await tester.pumpWidget(_buildScreen(cubit));

      // Lockout expires
      cubit.emit(const Unauthenticated());
      await tester.pump();

      // Button should now be enabled
      final elevatedButtons = tester.widgetList<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(
        elevatedButtons.any((btn) => btn.onPressed != null),
        isTrue,
        reason: 'Authenticate button must be enabled after lockout expires',
      );

      await cubit.close();
    });
  });
}
