import '../domain/entities/account_status.dart';
import '../domain/entities/session.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';
import 'record_failed_login.dart';
import 'session_manager.dart';
import '../../../../core/time/clock.dart';

/// The result of an [AuthenticateUser] call.
sealed class AuthResult {
  const AuthResult();
}

/// Authentication succeeded. The [session] has been registered with the
/// [SessionManager] and is now active.
final class AuthSuccess extends AuthResult {
  const AuthSuccess(this.session);
  final Session session;
}

/// The account has an active login-delay penalty. The caller should show a
/// countdown and prevent new attempts until [remainingSeconds] have elapsed.
final class AuthLoginDelayed extends AuthResult {
  const AuthLoginDelayed({required this.remainingSeconds});
  final int remainingSeconds;
}

/// The provided credentials are wrong, or the account does not exist.
///
/// The two cases are intentionally indistinguishable to callers so that
/// neither the username nor the password can be probed separately.
final class AuthInvalidCredentials extends AuthResult {
  const AuthInvalidCredentials();
}

/// The account has been suspended by the administrator. No credentials were
/// checked. The user should be shown a generic "contact administrator" message.
final class AuthAccountSuspended extends AuthResult {
  const AuthAccountSuspended();
}

/// Verifies user credentials, enforces existing login delays, and — on
/// success — creates a session via [SessionManager].
///
/// On credential failure delegates to [RecordFailedLogin] to apply the delay
/// schedule and auto-suspend the account after repeated failures.
class AuthenticateUser {
  const AuthenticateUser({
    required this._accounts,
    required this._hasher,
    required this._sessionManager,
    required this._auditLog,
    required this._clock,
    required this._recordFailedLogin,
  });

  final AccountRepository _accounts;
  final PasswordHasher _hasher;
  final SessionManager _sessionManager;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;
  final RecordFailedLogin _recordFailedLogin;

  Future<AuthResult> call({
    required String username,
    required String password,
  }) async {
    final account = await _accounts.findByUsername(username);

    if (account == null) {
      return const AuthInvalidCredentials();
    }

    if (account.status == AccountStatus.suspended) {
      return const AuthAccountSuspended();
    }

    final securityState = await _accounts.getSecurityState(account.internalId);
    if (securityState?.unlockNotBefore != null) {
      final now = _clock.nowUtc();
      if (now.isBefore(securityState!.unlockNotBefore!)) {
        final remaining = securityState.unlockNotBefore!
            .difference(now)
            .inSeconds;
        return AuthLoginDelayed(remainingSeconds: remaining);
      }
    }

    final valid = await _hasher.verify(password, account.passwordHash);
    if (!valid) {
      await _recordFailedLogin(account.internalId);
      return const AuthInvalidCredentials();
    }

    final now = _clock.nowUtc();
    await _accounts.resetSecurityState(account.internalId, now);
    await _auditLog.insertEvent(
      eventTypeKey: 'login_success',
      actorAccountId: account.internalId,
    );

    final session = Session(
      accountId: account.internalId,
      username: account.username,
      role: account.role,
      startedAt: now,
      isRestrictedToPasswordChange: account.mustChangePassword,
    );
    _sessionManager.login(session);
    return AuthSuccess(session);
  }
}
