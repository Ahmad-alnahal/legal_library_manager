import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/account_role.dart';
import '../../domain/entities/account_status.dart';
import '../../domain/entities/failed_login_state.dart';
import '../../domain/repositories/account_repository.dart';

class DriftAccountRepository implements AccountRepository {
  const DriftAccountRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Account?> findByUsername(String username) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((t) => t.username.equals(username))).getSingleOrNull();
    return row == null ? null : _toAccount(row);
  }

  @override
  Future<Account?> findById(String internalId) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((t) => t.internalId.equals(internalId))).getSingleOrNull();
    return row == null ? null : _toAccount(row);
  }

  @override
  Future<void> insertAccount(Account account) async {
    await _db.into(_db.accounts).insert(_toCompanion(account));
  }

  @override
  Future<void> updateAccount(Account account) async {
    await (_db.update(_db.accounts)
          ..where((t) => t.internalId.equals(account.internalId)))
        .write(_toCompanion(account));
  }

  @override
  Future<FailedLoginState?> getSecurityState(String accountId) async {
    final row = await (_db.select(
      _db.accountSecurityStates,
    )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();
    return row == null ? null : _toState(row);
  }

  @override
  Future<void> upsertSecurityState(
    String accountId,
    FailedLoginState state,
  ) async {
    await _db
        .into(_db.accountSecurityStates)
        .insertOnConflictUpdate(
          AccountSecurityStatesCompanion(
            accountId: Value(accountId),
            consecutiveFailures: Value(state.consecutiveFailures),
            unlockNotBefore: Value(
              state.unlockNotBefore?.toUtc().toIso8601String(),
            ),
            lastFailedAt: Value(state.lastFailedAt?.toUtc().toIso8601String()),
            lastSucceededAt: Value(
              state.lastSucceededAt?.toUtc().toIso8601String(),
            ),
            recoveryAttemptCount: Value(state.recoveryAttemptCount),
            recoveryWindowStart: Value(
              state.recoveryWindowStart?.toUtc().toIso8601String(),
            ),
          ),
        );
  }

  @override
  Future<void> resetSecurityState(
    String accountId,
    DateTime succeededAt,
  ) async {
    await _db
        .into(_db.accountSecurityStates)
        .insertOnConflictUpdate(
          AccountSecurityStatesCompanion(
            accountId: Value(accountId),
            consecutiveFailures: const Value(0),
            unlockNotBefore: const Value(null),
            lastFailedAt: const Value(null),
            lastSucceededAt: Value(succeededAt.toUtc().toIso8601String()),
            recoveryAttemptCount: const Value(0),
            recoveryWindowStart: const Value(null),
          ),
        );
  }

  Account _toAccount(AccountRow row) => Account(
    internalId: row.internalId,
    username: row.username,
    displayName: row.displayName,
    role: AccountRole.values.firstWhere((r) => r.name == row.roleKey),
    status: AccountStatus.values.firstWhere((s) => s.name == row.statusKey),
    mustChangePassword: row.mustChangePassword,
    passwordHash: row.passwordHash,
    createdAt: DateTime.parse(row.createdAt).toUtc(),
    updatedAt: DateTime.parse(row.updatedAt).toUtc(),
    createdById: row.createdById,
  );

  AccountsCompanion _toCompanion(Account account) => AccountsCompanion(
    internalId: Value(account.internalId),
    username: Value(account.username),
    displayName: Value(account.displayName),
    roleKey: Value(account.role.name),
    statusKey: Value(account.status.name),
    mustChangePassword: Value(account.mustChangePassword),
    passwordHash: Value(account.passwordHash),
    createdAt: Value(account.createdAt.toUtc().toIso8601String()),
    updatedAt: Value(account.updatedAt.toUtc().toIso8601String()),
    createdById: Value(account.createdById),
  );

  @override
  Future<void> upsertRecoveryCredentials(
    String accountId,
    String keyHash,
    DateTime createdAt,
  ) async {
    await _db
        .into(_db.recoveryCredentials)
        .insertOnConflictUpdate(
          RecoveryCredentialsCompanion(
            accountId: Value(accountId),
            keyHash: Value(keyHash),
            algorithmKey: const Value('argon2id'),
            createdAt: Value(createdAt.toUtc().toIso8601String()),
            lastUsedAt: const Value(null),
          ),
        );
  }

  @override
  Future<List<Account>> listOperators() async {
    final rows =
        await (_db.select(_db.accounts)
              ..where((t) => t.roleKey.equals(AccountRole.operator.name))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows.map(_toAccount).toList();
  }

  @override
  Future<bool> hasRecoveryCredentials(String accountId) async {
    final row = await (_db.select(
      _db.recoveryCredentials,
    )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<String?> getRecoveryKeyHash(String accountId) async {
    final row = await (_db.select(
      _db.recoveryCredentials,
    )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();
    return row?.keyHash;
  }

  FailedLoginState _toState(AccountSecurityState row) => FailedLoginState(
    consecutiveFailures: row.consecutiveFailures,
    unlockNotBefore: row.unlockNotBefore == null
        ? null
        : DateTime.parse(row.unlockNotBefore!).toUtc(),
    lastFailedAt: row.lastFailedAt == null
        ? null
        : DateTime.parse(row.lastFailedAt!).toUtc(),
    lastSucceededAt: row.lastSucceededAt == null
        ? null
        : DateTime.parse(row.lastSucceededAt!).toUtc(),
    recoveryAttemptCount: row.recoveryAttemptCount,
    recoveryWindowStart: row.recoveryWindowStart == null
        ? null
        : DateTime.parse(row.recoveryWindowStart!).toUtc(),
  );
}
