import '../../../../core/time/clock.dart';
import '../domain/entities/account_role.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';
import 'session_manager.dart';
import 'set_initial_admin_password.dart' show WeakPasswordException;
import 'unauthorized_exception.dart';

/// Issues a new temporary password for an existing operator account.
///
/// Sets [mustChangePassword] = true so the operator is forced to change the
/// password on their next login.
///
/// Throws [UnauthorizedException] if the current session is not admin.
class IssueTemporaryPassword {
  const IssueTemporaryPassword({
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

  /// Issues a new [temporaryPassword] for [operatorId].
  ///
  /// Throws [UnauthorizedException] if the current session is not admin.
  /// Throws [ArgumentError] if the account is not found.
  /// Throws [WeakPasswordException] if [temporaryPassword] is shorter than 8 chars.
  ///
  /// DEFERRED(step-up-auth): Step-up password re-verification before sensitive
  /// admin operations is not yet implemented. See M14_report.md §"Known Gaps".
  Future<void> call({
    required String operatorId,
    required String temporaryPassword,
    required String actorAccountId,
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      throw const UnauthorizedException('Admin role required.');
    }

    if (temporaryPassword.length < 8) {
      throw const WeakPasswordException('Password must be at least 8 characters.');
    }

    final account = await _accounts.findById(operatorId);
    if (account == null) throw ArgumentError('Account not found: $operatorId');

    final now = _clock.nowUtc();
    final newHash = await _hasher.hash(temporaryPassword);

    await _accounts.updateAccount(
      account.copyWith(
        passwordHash: newHash,
        mustChangePassword: true,
        updatedAt: now,
      ),
    );

    await _auditLog.insertEvent(
      eventTypeKey: 'temp_password_issued',
      actorAccountId: actorAccountId,
      targetAccountId: operatorId,
    );
  }
}
