import '../../../../core/time/clock.dart';
import '../domain/entities/account_status.dart';
import '../domain/entities/failed_login_state.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';
import 'bootstrap_admin_account.dart' show kSentinelPasswordHash;
import 'session_manager.dart';
import 'set_initial_admin_password.dart' show generateRecoveryKey;

/// Thrown when the provided recovery key does not match the stored hash, or
/// when no recovery credentials have been set up.
class InvalidRecoveryKeyException implements Exception {
  const InvalidRecoveryKeyException();
  @override
  String toString() => 'InvalidRecoveryKeyException';
}

/// Thrown when too many recovery attempts have been made within the current
/// throttle window.
class RecoveryKeyThrottledException implements Exception {
  const RecoveryKeyThrottledException(this.remainingSeconds);
  final int remainingSeconds;
  @override
  String toString() =>
      'RecoveryKeyThrottledException: $remainingSeconds seconds remaining';
}

/// Redeems the administrator's offline recovery key.
///
/// On success:
/// 1. Resets the admin's password to the sentinel hash (login impossible
///    until [SetInitialAdminPassword] runs again).
/// 2. Clears any suspension on the admin account.
/// 3. Resets the security state (login failures and recovery throttle).
/// 4. Invalidates the active session (if any).
/// 5. Rotates the recovery credential — a new key hash is stored and the
///    raw new key is returned for one-time display.
/// 6. Records a `recovery_key_redeemed` audit event.
///
/// After [call] returns, [AuthGatePage] sees [Unauthenticated] and routes to
/// [InitialSetupPage] because `admin.mustChangePassword == true`.
class RedeemRecoveryKey {
  static const _maxAttemptsPerWindow = 3;
  static const _windowDuration = Duration(minutes: 15);

  const RedeemRecoveryKey({
    required this._accounts,
    required this._hasher,
    required this._auditLog,
    required this._clock,
    required this._sessionManager,
  });

  final AccountRepository _accounts;
  final PasswordHasher _hasher;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;
  final SessionManager _sessionManager;

  /// Redeems [recoveryKey] for the admin account.
  ///
  /// Returns the new raw recovery key for one-time display.
  ///
  /// Throws [RecoveryKeyThrottledException] if the throttle window is active.
  /// Throws [InvalidRecoveryKeyException] if [recoveryKey] is incorrect or no
  /// recovery credential exists.
  Future<String> call(String recoveryKey) async {
    final now = _clock.nowUtc();

    final state =
        await _accounts.getSecurityState('admin') ??
        const FailedLoginState(consecutiveFailures: 0);

    final windowStart = state.recoveryWindowStart;
    int attemptCount = state.recoveryAttemptCount;

    if (windowStart != null && now.difference(windowStart) < _windowDuration) {
      if (attemptCount >= _maxAttemptsPerWindow) {
        final remaining =
            _windowDuration.inSeconds - now.difference(windowStart).inSeconds;
        throw RecoveryKeyThrottledException(
          remaining.clamp(1, _windowDuration.inSeconds),
        );
      }
    } else {
      attemptCount = 0;
    }

    final storedHash = await _accounts.getRecoveryKeyHash('admin');
    if (storedHash == null) throw const InvalidRecoveryKeyException();

    final valid = await _hasher.verify(recoveryKey, storedHash);
    if (!valid) {
      final newCount = attemptCount + 1;
      await _accounts.upsertSecurityState(
        'admin',
        state.copyWith(
          recoveryAttemptCount: newCount,
          recoveryWindowStart: windowStart ?? now,
        ),
      );
      throw const InvalidRecoveryKeyException();
    }

    final admin = await _accounts.findById('admin');
    if (admin == null) throw StateError('Admin account not found.');

    await _accounts.updateAccount(
      admin.copyWith(
        passwordHash: kSentinelPasswordHash,
        mustChangePassword: true,
        status: AccountStatus.active,
        updatedAt: now,
      ),
    );

    await _accounts.resetSecurityState('admin', now);

    _sessionManager.invalidateAll();

    final newRawKey = generateRecoveryKey();
    final newKeyHash = await _hasher.hash(newRawKey);
    await _accounts.upsertRecoveryCredentials('admin', newKeyHash, now);

    await _auditLog.insertEvent(
      eventTypeKey: 'recovery_key_redeemed',
      actorAccountId: 'admin',
    );

    return newRawKey;
  }
}
