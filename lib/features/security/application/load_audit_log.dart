import '../domain/entities/account_role.dart';
import '../domain/entities/security_audit_event.dart';
import '../domain/repositories/security_audit_repository.dart';
import 'session_manager.dart';
import 'unauthorized_exception.dart';

/// Loads a paginated page of security audit events, newest-first.
///
/// Enforces that only an active administrator session may read the audit log.
/// Operators and unauthenticated callers receive [UnauthorizedException].
class LoadAuditLog {
  const LoadAuditLog({
    required this._auditLog,
    required this._sessionManager,
  });

  final SecurityAuditRepository _auditLog;
  final SessionManager _sessionManager;

  /// Returns at most [limit] events starting at [offset], newest-first.
  ///
  /// Throws [UnauthorizedException] if the current session is not admin.
  Future<List<SecurityAuditEvent>> call({
    required int limit,
    required int offset,
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      throw const UnauthorizedException(
          'Admin role required to view the security audit log.');
    }
    return _auditLog.loadEvents(limit: limit, offset: offset);
  }
}
