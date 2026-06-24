import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/security_audit_event.dart';
import '../../domain/repositories/security_audit_repository.dart';

/// Append-only Drift implementation of [SecurityAuditRepository].
///
/// This class is insert-only — rows are never modified or removed. The
/// append-only invariant is enforced here and verified statically by the
/// security architecture test.
class DriftSecurityAuditRepository implements SecurityAuditRepository {
  const DriftSecurityAuditRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> insertEvent({
    required String eventTypeKey,
    String? actorAccountId,
    String? targetAccountId,
    String? eventDataSafe,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.into(_db.securityAuditLog).insert(
          SecurityAuditLogCompanion.insert(
            eventTypeKey: eventTypeKey,
            createdAt: now,
            actorAccountId: Value(actorAccountId),
            targetAccountId: Value(targetAccountId),
            eventDataSafe: Value(eventDataSafe),
          ),
        );
  }

  @override
  Future<List<SecurityAuditEvent>> loadEvents({
    required int limit,
    required int offset,
  }) async {
    final rows = await (_db.select(_db.securityAuditLog)
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
          ..limit(limit, offset: offset))
        .get();
    return rows.map(_toEvent).toList(growable: false);
  }

  SecurityAuditEvent _toEvent(SecurityAuditLogRow row) => SecurityAuditEvent(
        id: row.id,
        eventTypeKey: row.eventTypeKey,
        createdAt: DateTime.parse(row.createdAt).toUtc(),
        actorAccountId: row.actorAccountId,
        targetAccountId: row.targetAccountId,
        eventDataSafe: row.eventDataSafe,
      );
}
