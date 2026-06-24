import '../../../../core/time/clock.dart';
import '../domain/entities/account_role.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';
import 'session_manager.dart';
import 'set_initial_admin_password.dart' show WeakPasswordException;
import 'step_up_manager.dart';
import 'step_up_required_exception.dart';
import 'unauthorized_exception.dart';

/// Issues a new temporary password for an existing operator account.
///
/// Sets [mustChangePassword] = true so the operator is forced to change the
/// password on their next login.
///
/// Throws [UnauthorizedException] if the current session is not admin.
/// Throws [StepUpRequiredException] if no fresh step-up approval exists.
class IssueTemporaryPassword {
  const IssueTemporaryPassword({
    required this._accounts,
    required this._hasher,
    required this._auditLog,
    required this._clock,
    required this._sessionManager,
    required this._stepUpManager,
  });

  final AccountRepository _accounts;
  final PasswordHasher _hasher;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;
  final SessionManager _sessionManager;
  final StepUpManager _stepUpManager;

  /// Issues a new [temporaryPassword] for [operatorId].
  ///
  /// Throws [UnauthorizedException] if the current session is not admin.
  /// Throws [StepUpRequiredException] if no fresh step-up approval exists.
  /// Throws [ArgumentError] if the account is not found.
  /// Throws [WeakPasswordException] if [temporaryPassword] is shorter than 8 chars.
  Future<void> call({
    required String operatorId,
    required String temporaryPassword,
    required String actorAccountId,
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      throw const UnauthorizedException('Admin role required.');
    }
    if (!_stepUpManager.isApproved) {
      throw const StepUpRequiredException();
    }

    if (temporaryPassword.length < 8) {
      throw const WeakPasswordException(
        'Password must be at least 8 characters.',
      );
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
