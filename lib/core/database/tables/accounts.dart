// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

/// Account records for administrator and operator users (M14 security spec).
///
/// The [internalId] is immutable after creation ('admin' for the administrator,
/// a stable UUID for each operator). [username] is unique and display-editable
/// by the administrator for operator accounts only. Passwords are stored as
/// Argon2id PHC-format hashes — never in plaintext or reversible form.
/// [createdById] is self-referential and SET NULL when the creator is removed.
@DataClassName('AccountRow')
@TableIndex(name: 'ux_accounts_username', columns: {#username}, unique: true)
@TableIndex(name: 'ix_accounts_role_key', columns: {#roleKey})
@TableIndex(name: 'ix_accounts_status_key', columns: {#statusKey})
class Accounts extends Table {
  @override
  String get tableName => 'accounts';

  TextColumn get internalId => text()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  // CHECK (role_key IN ('admin', 'operator'))
  TextColumn get roleKey =>
      text().check(roleKey.isIn(const ['admin', 'operator']))();
  // CHECK (status_key IN ('active', 'suspended', 'disabled'))
  TextColumn get statusKey => text()
      .withDefault(const Constant('active'))
      .check(statusKey.isIn(const ['active', 'suspended', 'disabled']))();
  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(false))();
  TextColumn get passwordHash => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  // Self-referential: the account that created this one. SET NULL if creator
  // is later disabled/removed (though accounts are never physically deleted).
  TextColumn get createdById => text().nullable().references(
    Accounts,
    #internalId,
    onDelete: KeyAction.setNull,
  )();

  @override
  Set<Column<Object>> get primaryKey => {internalId};
}
