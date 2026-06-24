import '../../../../core/time/clock.dart';
import '../domain/entities/account_status.dart';
import '../domain/entities/failed_login_state.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';

/// Delay in seconds applied after each consecutive login failure.
///
/// Keys are the new failure count after the failed attempt. The account is
/// auto-suspended when [_autoSuspendAfter] failures are reached.
const Map<int, int> kLoginDelaySchedule = {1: 10, 2: 30, 3: 60};

/// Number of consecutive failures that triggers automatic account suspension.
const int kAutoSuspendAfter = 4;

/// Records a failed login attempt for [accountId].
///
/// Increments [FailedLoginState.consecutiveFailures] and applies the delay
/// schedule. Once [kAutoSuspendAfter] failures are reached the account is
/// suspended and an `account_auto_suspended` audit event is recorded.
/// An `login_failed` audit event is always recorded.
class RecordFailedLogin {
  const RecordFailedLogin({
    required this._accounts,
    required this._auditLog,
    required this._clock,
  });

  final AccountRepository _accounts;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;

  Future<void> call(String accountId) async {
    final now = _clock.nowUtc();
    final existing = await _accounts.getSecurityState(accountId) ??
        const FailedLoginState(consecutiveFailures: 0);
    final newFailures = existing.consecutiveFailures + 1;

    await _auditLog.insertEvent(
      eventTypeKey: 'login_failed',
      actorAccountId: accountId,
    );

    if (newFailures >= kAutoSuspendAfter) {
      final account = await _accounts.findById(accountId);
      if (account != null && account.status != AccountStatus.suspended) {
        await _accounts.updateAccount(
          account.copyWith(status: AccountStatus.suspended),
        );
        await _auditLog.insertEvent(
          eventTypeKey: 'account_auto_suspended',
          actorAccountId: accountId,
          targetAccountId: accountId,
        );
      }
      await _accounts.upsertSecurityState(
        accountId,
        existing.copyWith(
          consecutiveFailures: newFailures,
          lastFailedAt: now,
          clearUnlockNotBefore: true,
        ),
      );
    } else {
      final delaySecs = kLoginDelaySchedule[newFailures]!;
      final unlockNotBefore = now.add(Duration(seconds: delaySecs));
      await _accounts.upsertSecurityState(
        accountId,
        FailedLoginState(
          consecutiveFailures: newFailures,
          unlockNotBefore: unlockNotBefore,
          lastFailedAt: now,
          lastSucceededAt: existing.lastSucceededAt,
          recoveryAttemptCount: existing.recoveryAttemptCount,
          recoveryWindowStart: existing.recoveryWindowStart,
        ),
      );
    }
  }
}
