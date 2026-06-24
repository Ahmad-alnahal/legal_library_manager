// lib/features/security/application/verify_admin_step_up.dart

import '../domain/entities/account_role.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';
import 'session_manager.dart';
import 'step_up_manager.dart';
import 'unauthorized_exception.dart';

/// Result of a step-up password verification attempt.
sealed class StepUpVerifyResult {
  const StepUpVerifyResult();
}

/// The admin password was correct and step-up approval has been granted.
final class StepUpVerifySuccess extends StepUpVerifyResult {
  const StepUpVerifySuccess();
}

/// The provided password did not match the stored admin password hash.
final class StepUpVerifyWrongPassword extends StepUpVerifyResult {
  const StepUpVerifyWrongPassword();
}

/// Verifies the current administrator's password to grant a short-lived
/// step-up authentication approval.
///
/// Step-up approval is required for sensitive administrative operations such as
/// account management, protected storage-path changes, manual database backup,
/// and managed-copy integrity reconciliation.
///
/// Throws [UnauthorizedException] if there is no active admin session.
class VerifyAdminStepUp {
  const VerifyAdminStepUp({
    required this._accounts,
    required this._hasher,
    required this._auditLog,
    required this._sessionManager,
    required this._stepUpManager,
  });

  final AccountRepository _accounts;
  final PasswordHasher _hasher;
  final SecurityAuditRepository _auditLog;
  final SessionManager _sessionManager;
  final StepUpManager _stepUpManager;

  /// Verifies [password] against the current admin account's Argon2id hash.
  ///
  /// On success: calls [StepUpManager.grant()] and records `step_up_granted`.
  /// Returns [StepUpVerifySuccess].
  ///
  /// On wrong password: records `step_up_denied`. Returns
  /// [StepUpVerifyWrongPassword]. Any prior step-up state is unchanged.
  ///
  /// Throws [UnauthorizedException] if no active admin session exists.
  Future<StepUpVerifyResult> call(String password) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      throw const UnauthorizedException(
        'Active admin session required for step-up.',
      );
    }

    final account = await _accounts.findById(session.accountId);
    if (account == null) {
      throw const UnauthorizedException('Admin account not found.');
    }

    final valid = await _hasher.verify(password, account.passwordHash);

    if (valid) {
      _stepUpManager.grant();
      await _audit('step_up_granted', session.accountId);
      return const StepUpVerifySuccess();
    } else {
      await _audit('step_up_denied', session.accountId);
      return const StepUpVerifyWrongPassword();
    }
  }

  Future<void> _audit(String eventTypeKey, String actorId) async {
    try {
      await _auditLog.insertEvent(
        eventTypeKey: eventTypeKey,
        actorAccountId: actorId,
      );
    } catch (_) {
      // Audit failures must not mask the step-up result.
    }
  }
}
