import 'package:drift/drift.dart';

import 'accounts.dart';

/// Per-account failed-login counters, delay timestamps, and recovery
/// rate-limiting state (M14 security spec §failed-login policy).
///
/// One row per account; the row is created on first failure and reset to
/// defaults on a successful login. [unlockNotBefore] is an ISO-8601 UTC
/// timestamp: login attempts are rejected until the system clock is past it.
/// [lastFailedAt] is used to detect clock rollback — if the system clock
/// moves behind [lastFailedAt] on a subsequent attempt, the delay is extended
/// rather than cleared. [recoveryAttemptCount] and [recoveryWindowStart]
/// are separate from the login failure state to allow the admin to log in
/// normally while rate-limiting offline recovery attempts.
class AccountSecurityStates extends Table {
  @override
  String get tableName => 'account_security_state';

  TextColumn get accountId =>
      text().references(Accounts, #internalId, onDelete: KeyAction.cascade)();
  IntColumn get consecutiveFailures =>
      integer().withDefault(const Constant(0))();
  TextColumn get unlockNotBefore => text().nullable()();
  TextColumn get lastFailedAt => text().nullable()();
  TextColumn get lastSucceededAt => text().nullable()();
  IntColumn get recoveryAttemptCount =>
      integer().withDefault(const Constant(0))();
  TextColumn get recoveryWindowStart => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {accountId};
}
