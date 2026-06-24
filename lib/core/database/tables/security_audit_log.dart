import 'package:drift/drift.dart';

import 'accounts.dart';

/// Append-only security event log (M14 security spec §security-audit-log).
///
/// Records every authentication, authorization, account-lifecycle, and
/// recovery event. Rows are never updated or deleted — this invariant is
/// enforced at the repository layer (SecurityAuditRepository has no update
/// or delete methods) and verified by the security architecture test.
///
/// Policy: [eventDataSafe] must never contain document contents, file paths
/// beyond safe IDs, passwords, keys, or secrets. [actorAccountId] and
/// [targetAccountId] reference accounts but are SET NULL if the referenced
/// account is removed (accounts are not physically deleted in practice, so
/// this is a safety net only).
@DataClassName('SecurityAuditLogRow')
@TableIndex(name: 'ix_security_audit_log_created_at', columns: {#createdAt})
@TableIndex(name: 'ix_security_audit_log_event_type', columns: {#eventTypeKey})
@TableIndex(name: 'ix_security_audit_log_actor', columns: {#actorAccountId})
class SecurityAuditLog extends Table {
  @override
  String get tableName => 'security_audit_log';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get eventTypeKey => text()();
  TextColumn get actorAccountId => text().nullable().references(
    Accounts,
    #internalId,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get targetAccountId => text().nullable().references(
    Accounts,
    #internalId,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get eventDataSafe => text().nullable()();
  TextColumn get createdAt => text()();
}
