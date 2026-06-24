import '../../../../core/time/clock.dart';
import '../domain/entities/account_role.dart';
import '../domain/entities/account_status.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import 'session_manager.dart';
import 'step_up_manager.dart';
import 'step_up_required_exception.dart';
import 'unauthorized_exception.dart';

/// Updates the mutable fields of an operator account.
///
/// Throws [UnauthorizedException] if the current session is not admin.
/// Throws [StepUpRequiredException] if no fresh step-up approval exists.
class UpdateOperatorAccount {
  const UpdateOperatorAccount({
    required this._accounts,
    required this._auditLog,
    required this._clock,
    required this._sessionManager,
    required this._stepUpManager,
  });

  final AccountRepository _accounts;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;
  final SessionManager _sessionManager;
  final StepUpManager _stepUpManager;

  /// Updates [displayName] and/or [status] for [operatorId].
  ///
  /// Throws [UnauthorizedException] if the current session is not admin.
  /// Throws [StepUpRequiredException] if no fresh step-up approval exists.
  /// Throws [ArgumentError] if [operatorId] is not found.
  Future<void> call({
    required String operatorId,
    String? displayName,
    AccountStatus? status,
    required String actorAccountId,
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      throw const UnauthorizedException('Admin role required.');
    }
    if (!_stepUpManager.isApproved) {
      throw const StepUpRequiredException();
    }

    final account = await _accounts.findById(operatorId);
    if (account == null) throw ArgumentError('Account not found: $operatorId');

    final now = _clock.nowUtc();
    await _accounts.updateAccount(
      account.copyWith(
        displayName: displayName,
        status: status,
        updatedAt: now,
      ),
    );

    if (status == AccountStatus.suspended) {
      await _auditLog.insertEvent(
        eventTypeKey: 'account_suspended',
        actorAccountId: actorAccountId,
        targetAccountId: operatorId,
      );
    } else if (status == AccountStatus.active) {
      await _auditLog.insertEvent(
        eventTypeKey: 'account_reactivated',
        actorAccountId: actorAccountId,
        targetAccountId: operatorId,
      );
    }
  }
}
