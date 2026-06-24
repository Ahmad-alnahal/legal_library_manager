import '../entities/security_audit_event.dart';

/// Persistence-agnostic contract for the append-only security audit log.
///
/// This repository intentionally has NO update or delete methods. The audit
/// log is permanent. Implementations must enforce this invariant and the
/// security architecture test verifies it statically.
abstract class SecurityAuditRepository {
  /// Appends a new security event to the log. [eventDataSafe] must not
  /// contain passwords, keys, file paths, or document contents.
  Future<void> insertEvent({
    required String eventTypeKey,
    String? actorAccountId,
    String? targetAccountId,
    String? eventDataSafe,
  });

  /// Returns the most recent [limit] events, offset by [offset], sorted
  /// newest-first. Used by the admin-only security audit viewer.
  Future<List<SecurityAuditEvent>> loadEvents({
    required int limit,
    required int offset,
  });
}
