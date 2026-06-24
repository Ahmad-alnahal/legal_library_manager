import 'package:drift/drift.dart';

import 'accounts.dart';

/// Hashed offline recovery key for the administrator account (M14 security
/// spec §administrator-recovery).
///
/// Only the Argon2id hash of the recovery key is stored — the raw key is
/// displayed once to the administrator during setup and then discarded. Using
/// the recovery key invalidates this row, inserts a new one with a freshly
/// generated key hash, and invalidates all active sessions. One row per
/// account (currently only the admin account has a recovery credential).
class RecoveryCredentials extends Table {
  @override
  String get tableName => 'recovery_credentials';

  TextColumn get accountId =>
      text().references(Accounts, #internalId, onDelete: KeyAction.cascade)();
  TextColumn get keyHash => text()();
  TextColumn get algorithmKey =>
      text().withDefault(const Constant('argon2id'))();
  TextColumn get createdAt => text()();
  TextColumn get lastUsedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {accountId};
}
