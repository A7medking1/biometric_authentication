import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:for_learning/blocs/auth_cubit.dart';
import 'package:for_learning/blocs/auth_state.dart';
import 'package:for_learning/local_auth_service.dart';
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

AuthCubit _cubit({
  required AuthResult Function() result,
  MockRateLimitStorageService? storage,
}) {
  return AuthCubit(
    storageService: storage ?? _mockStorage(),
    authenticate: ({reason = '', biometricOnly = false}) async => result(),
  );
}

/// Trigger [count] consecutive failures on [cubit] and flush microtasks each time.
Future<void> _fail(AuthCubit cubit, int count) async {
  for (var i = 0; i < count; i++) {
    await cubit.authenticate();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// US1 — Lockout After Repeated Failures (FR-001, FR-002, FR-010–FR-012, FR-015)
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RateLimitRecord(failedAttemptCount: 0, escalationLevel: 0),
    );
  });

  group('US1 — Lockout after repeated failures', () {
    test(
        '(a) failures 1–4 each emit AuthError and do NOT emit AuthRateLimited',
        () async {
      final cubit = _cubit(result: () => AuthResult.failed);

      final states = <AuthState>[];
      final sub = cubit.stream.listen(states.add);

      await _fail(cubit, 4);

      // Every emitted non-loading state should be AuthError, never AuthRateLimited
      final nonLoading = states.where((s) => s is! AuthLoading).toList();
      expect(nonLoading, hasLength(4));
      for (final s in nonLoading) {
        expect(s, isA<AuthError>());
      }
      expect(states.whereType<AuthRateLimited>(), isEmpty);

      await sub.cancel();
      await cubit.close();
    });

    test('(b) 5th failure emits AuthRateLimited directly — no AuthError first',
        () async {
      final cubit = _cubit(result: () => AuthResult.failed);

      final states = <AuthState>[];
      final sub = cubit.stream.listen(states.add);

      await _fail(cubit, 5);

      // Last substantive state must be AuthRateLimited, not AuthError
      final substantive = states.where((s) => s is! AuthLoading).toList();
      expect(substantive.last, isA<AuthRateLimited>());
      // No AuthError emitted for the 5th failure
      expect(substantive.last, isNot(isA<AuthError>()));

      final limited = cubit.state as AuthRateLimited;
      expect(limited.remainingSeconds, equals(60));
      expect(limited.escalationLevel, equals(0));

      await sub.cancel();
      await cubit.close();
    });

    test(
        '(c) authenticate() while in AuthRateLimited returns immediately — auth not called',
        () async {
      var callCount = 0;
      final cubit = AuthCubit(
        storageService: _mockStorage(),
        authenticate: ({reason = '', biometricOnly = false}) async {
          callCount++;
          return AuthResult.failed;
        },
      );

      // Reach lockout
      await _fail(cubit, 5);
      expect(cubit.state, isA<AuthRateLimited>());

      final stateBefore = cubit.state;
      final callsBefore = callCount;

      await cubit.authenticate(); // should be a no-op

      expect(cubit.state, equals(stateBefore));
      expect(callCount, equals(callsBefore)); // auth not called again

      await cubit.close();
    });

    test(
        '(d) cancelled / notAvailable / notEnrolled do NOT increment counter',
        () async {
      // Cancel 4 times — counter should stay at 0
      final cubit = _cubit(result: () => AuthResult.cancelled);
      await _fail(cubit, 4);
      expect(cubit.state, isNot(isA<AuthRateLimited>()));

      // Now switch to notAvailable
      final cubit2 = _cubit(result: () => AuthResult.notAvailable);
      await _fail(cubit2, 4);
      expect(cubit2.state, isNot(isA<AuthRateLimited>()));

      // notEnrolled
      final cubit3 = _cubit(result: () => AuthResult.notEnrolled);
      await _fail(cubit3, 4);
      expect(cubit3.state, isNot(isA<AuthRateLimited>()));

      // Mixed: 4 cancellations then 4 failures should NOT lock out (only 4 real failures)
      var toggle = false;
      final cubit4 = AuthCubit(
        storageService: _mockStorage(),
        authenticate: ({reason = '', biometricOnly = false}) async {
          toggle = !toggle;
          return toggle ? AuthResult.cancelled : AuthResult.failed;
        },
      );
      await _fail(cubit4, 8); // 4 cancel + 4 fail
      expect(cubit4.state, isNot(isA<AuthRateLimited>()));

      await cubit.close();
      await cubit2.close();
      await cubit3.close();
      await cubit4.close();
    });

    test('(e) handleAppResumed while in AuthRateLimited does NOT emit AppLocked',
        () async {
      final cubit = _cubit(result: () => AuthResult.failed);
      await _fail(cubit, 5);
      expect(cubit.state, isA<AuthRateLimited>());

      cubit.handleAppResumed();

      expect(cubit.state, isA<AuthRateLimited>()); // unchanged

      await cubit.close();
    });

    test(
        '(f) notAvailable/notEnrolled while in AppLocked returns to AppLocked',
        () async {
      final lockedAt = DateTime(2026, 4, 15);

      for (final result in [AuthResult.notAvailable, AuthResult.notEnrolled]) {
        final cubit = AuthCubit(
          storageService: _mockStorage(),
          authenticate: ({reason = '', biometricOnly = false}) async => result,
        );
        // Manually put cubit in AppLocked by emitting via lockApp
        cubit.emit(AppLocked(lockedAt: lockedAt));
        expect(cubit.state, isA<AppLocked>());

        await cubit.authenticate();

        expect(cubit.state, isA<AppLocked>());
        await cubit.close();
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // US2 — Live Countdown (FR-003, FR-005, FR-013, FR-015)
  // ══════════════════════════════════════════════════════════════════════════

  group('US2 — Live countdown during lockout', () {
    test('(a) advancing 1 second decrements remainingSeconds by 1', () {
      fakeAsync((async) {
        final cubit = _cubit(result: () => AuthResult.failed);

        // Trigger lockout (run the async calls inside fakeAsync)
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }

        expect(cubit.state, isA<AuthRateLimited>());
        final initial = (cubit.state as AuthRateLimited).remainingSeconds;

        async.elapse(const Duration(seconds: 1));

        expect(cubit.state, isA<AuthRateLimited>());
        final after = (cubit.state as AuthRateLimited).remainingSeconds;
        expect(after, lessThan(initial));
        expect(after, greaterThanOrEqualTo(initial - 1));

        cubit.close();
        async.flushMicrotasks();
      });
    });

    test(
        '(b) at 0 s, emits AppLocked when lifecycleLock, Unauthenticated otherwise',
        () {
      // Case 1: from Unauthenticated context → Unauthenticated on expiry
      fakeAsync((async) {
        final cubit = _cubit(result: () => AuthResult.failed);
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect(cubit.state, isA<AuthRateLimited>());
        async.elapse(const Duration(seconds: 61)); // past 60 s lockout
        expect(cubit.state, isA<Unauthenticated>());
        cubit.close();
        async.flushMicrotasks();
      });

      // Case 2: from AppLocked context → AppLocked on expiry
      fakeAsync((async) {
        final cubit = AuthCubit(
          storageService: _mockStorage(),
          authenticate: ({reason = '', biometricOnly = false}) async =>
              AuthResult.failed,
        );
        cubit.emit(AppLocked(lockedAt: DateTime.now()));

        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect(cubit.state, isA<AuthRateLimited>());
        async.elapse(const Duration(seconds: 61));
        expect(cubit.state, isA<AppLocked>());
        cubit.close();
        async.flushMicrotasks();
      });
    });

    test('(c) timer is cancelled when cubit is closed', () {
      fakeAsync((async) {
        final cubit = _cubit(result: () => AuthResult.failed);
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect(cubit.state, isA<AuthRateLimited>());

        cubit.close();
        async.flushMicrotasks();

        // Advancing time after close should not crash or emit
        async.elapse(const Duration(seconds: 30));
        // No exception = timer was properly cancelled
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // US3 — Exponential Backoff (FR-006, FR-007)
  // ══════════════════════════════════════════════════════════════════════════

  group('US3 — Exponential backoff', () {
    test('(a) first lockout starts with remainingSeconds == 60', () async {
      final cubit = _cubit(result: () => AuthResult.failed);
      await _fail(cubit, 5);
      expect((cubit.state as AuthRateLimited).remainingSeconds, equals(60));
      await cubit.close();
    });

    test('(b) second lockout starts with remainingSeconds == 120', () {
      fakeAsync((async) {
        final cubit = _cubit(result: () => AuthResult.failed);

        // First lockout
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect((cubit.state as AuthRateLimited).remainingSeconds, equals(60));

        // Wait for first lockout to expire
        async.elapse(const Duration(seconds: 61));
        expect(cubit.state, isA<Unauthenticated>());

        // Second lockout
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect((cubit.state as AuthRateLimited).remainingSeconds, equals(120));

        cubit.close();
        async.flushMicrotasks();
      });
    });

    test('(c) third lockout starts with remainingSeconds == 240', () {
      fakeAsync((async) {
        final cubit = _cubit(result: () => AuthResult.failed);

        for (final lockoutDuration in [61, 121]) {
          for (var i = 0; i < 5; i++) {
            cubit.authenticate();
            async.flushMicrotasks();
          }
          async.elapse(Duration(seconds: lockoutDuration));
        }

        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect((cubit.state as AuthRateLimited).remainingSeconds, equals(240));

        cubit.close();
        async.flushMicrotasks();
      });
    });

    test('(d) fourth and beyond lockouts cap at 900 s', () {
      fakeAsync((async) {
        final cubit = _cubit(result: () => AuthResult.failed);

        for (final d in [61, 121, 241]) {
          for (var i = 0; i < 5; i++) {
            cubit.authenticate();
            async.flushMicrotasks();
          }
          async.elapse(Duration(seconds: d));
        }

        // 4th lockout
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect((cubit.state as AuthRateLimited).remainingSeconds, equals(900));

        // 5th lockout also caps
        async.elapse(const Duration(seconds: 901));
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect((cubit.state as AuthRateLimited).remainingSeconds, equals(900));

        cubit.close();
        async.flushMicrotasks();
      });
    });

    test(
        '(e) successful auth resets escalation so next lockout is 60 s',
        () {
      fakeAsync((async) {
        var nextResult = AuthResult.failed;
        final cubit = AuthCubit(
          storageService: _mockStorage(),
          authenticate: ({reason = '', biometricOnly = false}) async =>
              nextResult,
        );

        // First lockout (60 s)
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        async.elapse(const Duration(seconds: 61));
        expect(cubit.state, isA<Unauthenticated>());

        // Authenticate successfully → resets escalation
        nextResult = AuthResult.success;
        cubit.authenticate();
        async.flushMicrotasks();
        expect(cubit.state, isA<Authenticated>());

        // Next lockout should be 60 s again (level reset)
        nextResult = AuthResult.failed;
        for (var i = 0; i < 5; i++) {
          cubit.authenticate();
          async.flushMicrotasks();
        }
        expect((cubit.state as AuthRateLimited).remainingSeconds, equals(60));

        cubit.close();
        async.flushMicrotasks();
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // US4 — Secure Persistence (FR-008, FR-009)
  // ══════════════════════════════════════════════════════════════════════════

  group('US4 — Persistence', () {
    test('(a) saveRecord called on each failed attempt (1–4)', () async {
      final storage = _mockStorage();
      final cubit = _cubit(result: () => AuthResult.failed, storage: storage);

      await _fail(cubit, 4);

      verify(() => storage.saveRecord(any())).called(4);
      await cubit.close();
    });

    test(
        '(b) saveRecord called with lockoutStartMs and lockoutDurationSeconds when lockout starts',
        () async {
      final storage = _mockStorage();
      final cubit = _cubit(result: () => AuthResult.failed, storage: storage);

      await _fail(cubit, 5);

      final captured = verify(() => storage.saveRecord(captureAny()))
          .captured
          .cast<RateLimitRecord>();
      // Last save (on lockout start) should have non-null lockout fields
      final lockoutSave = captured.last;
      expect(lockoutSave.lockoutStartMs, isNotNull);
      expect(lockoutSave.lockoutDurationSeconds, isNotNull);
      expect(lockoutSave.lockoutDurationSeconds, equals(60));

      await cubit.close();
    });

    test(
        '(c) cubit init with active stored lockout → emits AuthRateLimited with correct remainingSeconds',
        () async {
      const durationS = 60;
      final startMs =
          DateTime.now().millisecondsSinceEpoch - 20 * 1000; // 20 s ago

      final storage = _mockStorage();
      when(() => storage.loadRecord()).thenAnswer(
        (_) async => RateLimitRecord(
          failedAttemptCount: 5,
          escalationLevel: 1,
          lockoutStartMs: startMs,
          lockoutDurationSeconds: durationS,
        ),
      );

      final cubit = AuthCubit(
        storageService: storage,
        authenticate: ({reason = '', biometricOnly = false}) async =>
            AuthResult.failed,
      );
      await cubit.checkDeviceCapabilities();

      expect(cubit.state, isA<AuthRateLimited>());
      final limited = cubit.state as AuthRateLimited;
      // 60 - 20 = 40 remaining (±1 for timing)
      expect(limited.remainingSeconds, closeTo(40, 2));

      await cubit.close();
    });

    test(
        '(d) cubit init with expired stored lockout → emits Unauthenticated and calls clearRecord',
        () async {
      final startMs =
          DateTime.now().millisecondsSinceEpoch - 90 * 1000; // 90 s ago

      final storage = _mockStorage();
      when(() => storage.loadRecord()).thenAnswer(
        (_) async => RateLimitRecord(
          failedAttemptCount: 5,
          escalationLevel: 1,
          lockoutStartMs: startMs,
          lockoutDurationSeconds: 60, // expired
        ),
      );

      final cubit = AuthCubit(
        storageService: storage,
        authenticate: ({reason = '', biometricOnly = false}) async =>
            AuthResult.failed,
      );
      await cubit.checkDeviceCapabilities();

      // Should proceed to normal check — mock returns no biometrics
      // (loadRecord returned record but lockout expired → clearRecord + normal check)
      verify(() => storage.clearRecord()).called(greaterThanOrEqualTo(1));

      await cubit.close();
    });

    test('(e) clearRecord called on successful authentication', () async {
      var nextResult = AuthResult.failed;
      final storage = _mockStorage();
      final cubit = AuthCubit(
        storageService: storage,
        authenticate: ({reason = '', biometricOnly = false}) async =>
            nextResult,
      );

      nextResult = AuthResult.success;
      await cubit.authenticate();

      verify(() => storage.clearRecord()).called(1);
      await cubit.close();
    });
  });
}
