import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted record of the current rate-limit state (all fields written to secure storage)
class RateLimitRecord {
  /// Consecutive failed attempts (0–5). Resets to 0 on success or lockout expiry.
  final int failedAttemptCount;

  /// Post-increment escalation level — the level to be used for the *next* lockout.
  /// Resets to 0 on successful authentication.
  final int escalationLevel;

  /// `DateTime.now().millisecondsSinceEpoch` at lockout start. null when not locked.
  final int? lockoutStartMs;

  /// Total lockout duration in seconds for the current event. null when not locked.
  final int? lockoutDurationSeconds;

  const RateLimitRecord({
    required this.failedAttemptCount,
    required this.escalationLevel,
    this.lockoutStartMs,
    this.lockoutDurationSeconds,
  });
}

/// Thin wrapper around [FlutterSecureStorage] for rate-limit state persistence.
/// Injected into [AuthCubit] to enable mocking in unit tests (Constitution Principle II, V).
class RateLimitStorageService {
  static const String _keyFailedCount = 'rl_failed_count';
  static const String _keyEscalationLevel = 'rl_escalation_level';
  static const String _keyLockoutStartMs = 'rl_lockout_start_ms';
  static const String _keyLockoutDurationS = 'rl_lockout_duration_s';

  final FlutterSecureStorage _storage;

  RateLimitStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Loads the persisted record. Returns null if no record has been saved yet.
  Future<RateLimitRecord?> loadRecord() async {
    final failedCountStr = await _storage.read(key: _keyFailedCount);
    if (failedCountStr == null) return null;

    final escalationLevelStr = await _storage.read(key: _keyEscalationLevel);
    final lockoutStartMsStr = await _storage.read(key: _keyLockoutStartMs);
    final lockoutDurationSStr = await _storage.read(key: _keyLockoutDurationS);

    return RateLimitRecord(
      failedAttemptCount: int.tryParse(failedCountStr) ?? 0,
      escalationLevel: int.tryParse(escalationLevelStr ?? '') ?? 0,
      lockoutStartMs:
          lockoutStartMsStr != null ? int.tryParse(lockoutStartMsStr) : null,
      lockoutDurationSeconds:
          lockoutDurationSStr != null ? int.tryParse(lockoutDurationSStr) : null,
    );
  }

  /// Persists the full record. Omits lockout keys when null (no active lockout).
  Future<void> saveRecord(RateLimitRecord record) async {
    await _storage.write(
      key: _keyFailedCount,
      value: record.failedAttemptCount.toString(),
    );
    await _storage.write(
      key: _keyEscalationLevel,
      value: record.escalationLevel.toString(),
    );
    if (record.lockoutStartMs != null) {
      await _storage.write(
        key: _keyLockoutStartMs,
        value: record.lockoutStartMs.toString(),
      );
    } else {
      await _storage.delete(key: _keyLockoutStartMs);
    }
    if (record.lockoutDurationSeconds != null) {
      await _storage.write(
        key: _keyLockoutDurationS,
        value: record.lockoutDurationSeconds.toString(),
      );
    } else {
      await _storage.delete(key: _keyLockoutDurationS);
    }
  }

  /// Clears all stored rate-limit keys (called on successful auth or lockout expiry).
  Future<void> clearRecord() async {
    await Future.wait([
      _storage.delete(key: _keyFailedCount),
      _storage.delete(key: _keyEscalationLevel),
      _storage.delete(key: _keyLockoutStartMs),
      _storage.delete(key: _keyLockoutDurationS),
    ]);
  }
}
