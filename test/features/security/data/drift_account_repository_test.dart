import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/domain/entities/account.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_status.dart';
import 'package:legal_library_manager/features/security/domain/entities/failed_login_state.dart';

Account _makeAccount({
  String id = 'admin',
  String username = 'marjiy@admin',
  AccountRole role = AccountRole.admin,
  AccountStatus status = AccountStatus.active,
  bool mustChange = true,
}) => Account(
  internalId: id,
  username: username,
  displayName: 'Display',
  role: role,
  status: status,
  mustChangePassword: mustChange,
  passwordHash: r'$sentinel$v=0$hash$',
  createdAt: DateTime.utc(2026, 6, 23, 10),
  updatedAt: DateTime.utc(2026, 6, 23, 10),
);

void main() {
  late AppDatabase db;
  late DriftAccountRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = DriftAccountRepository(db);
  });

  tearDown(() async => db.close());

  group('DriftAccountRepository', () {
    // ── findById ──────────────────────────────────────────────────────────

    test('findById returns null when account does not exist', () async {
      expect(await repo.findById('ghost'), isNull);
    });

    test('findById returns the account after insert', () async {
      await repo.insertAccount(_makeAccount());
      final found = await repo.findById('admin');
      expect(found, isNotNull);
      expect(found!.internalId, 'admin');
      expect(found.username, 'marjiy@admin');
    });

    // ── findByUsername ─────────────────────────────────────────────────────

    test('findByUsername returns null for unknown username', () async {
      expect(await repo.findByUsername('nobody@x'), isNull);
    });

    test('findByUsername returns the account after insert', () async {
      await repo.insertAccount(_makeAccount());
      final found = await repo.findByUsername('marjiy@admin');
      expect(found?.internalId, 'admin');
    });

    // ── insertAccount / updateAccount ──────────────────────────────────────

    test('insertAccount persists all fields correctly', () async {
      final account = _makeAccount(
        id: 'op1',
        username: 'op@test',
        role: AccountRole.operator,
        status: AccountStatus.suspended,
        mustChange: false,
      );
      await repo.insertAccount(account);
      final found = await repo.findById('op1');
      expect(found?.role, AccountRole.operator);
      expect(found?.status, AccountStatus.suspended);
      expect(found?.mustChangePassword, isFalse);
    });

    test('updateAccount persists changes', () async {
      await repo.insertAccount(_makeAccount());
      final updated = (await repo.findById('admin'))!.copyWith(
        mustChangePassword: false,
        status: AccountStatus.active,
        updatedAt: DateTime.utc(2026, 6, 24),
      );
      await repo.updateAccount(updated);
      final found = await repo.findById('admin');
      expect(found?.mustChangePassword, isFalse);
      expect(found?.updatedAt, DateTime.utc(2026, 6, 24));
    });

    // ── getSecurityState ───────────────────────────────────────────────────

    test('getSecurityState returns null before any failure', () async {
      await repo.insertAccount(_makeAccount());
      expect(await repo.getSecurityState('admin'), isNull);
    });

    // ── upsertSecurityState ────────────────────────────────────────────────

    test('upsertSecurityState inserts a new state row', () async {
      await repo.insertAccount(_makeAccount());
      final state = FailedLoginState(
        consecutiveFailures: 3,
        lastFailedAt: DateTime.utc(2026, 6, 23, 9),
        unlockNotBefore: DateTime.utc(2026, 6, 23, 10),
      );
      await repo.upsertSecurityState('admin', state);
      final found = await repo.getSecurityState('admin');
      expect(found?.consecutiveFailures, 3);
      expect(found?.unlockNotBefore, DateTime.utc(2026, 6, 23, 10));
    });

    test('upsertSecurityState overwrites existing state', () async {
      await repo.insertAccount(_makeAccount());
      await repo.upsertSecurityState(
        'admin',
        const FailedLoginState(consecutiveFailures: 2),
      );
      await repo.upsertSecurityState(
        'admin',
        const FailedLoginState(consecutiveFailures: 5),
      );
      final found = await repo.getSecurityState('admin');
      expect(found?.consecutiveFailures, 5);
    });

    test('upsertSecurityState persists nullable fields as null', () async {
      await repo.insertAccount(_makeAccount());
      await repo.upsertSecurityState(
        'admin',
        FailedLoginState(
          consecutiveFailures: 1,
          unlockNotBefore: DateTime.utc(2026, 6, 23, 12),
        ),
      );
      final state = await repo.getSecurityState('admin');
      // Now clear it
      await repo.upsertSecurityState(
        'admin',
        state!.copyWith(clearUnlockNotBefore: true),
      );
      final cleared = await repo.getSecurityState('admin');
      expect(cleared?.unlockNotBefore, isNull);
    });

    // ── resetSecurityState ─────────────────────────────────────────────────

    test('resetSecurityState zeroes failures and clears lock', () async {
      await repo.insertAccount(_makeAccount());
      await repo.upsertSecurityState(
        'admin',
        FailedLoginState(
          consecutiveFailures: 4,
          unlockNotBefore: DateTime.utc(2026, 6, 23, 15),
          lastFailedAt: DateTime.utc(2026, 6, 23, 14),
          recoveryAttemptCount: 2,
          recoveryWindowStart: DateTime.utc(2026, 6, 23, 13),
        ),
      );
      await repo.resetSecurityState('admin', DateTime.utc(2026, 6, 23, 16));
      final reset = await repo.getSecurityState('admin');
      expect(reset?.consecutiveFailures, 0);
      expect(reset?.unlockNotBefore, isNull);
      expect(reset?.lastFailedAt, isNull);
      expect(reset?.lastSucceededAt, DateTime.utc(2026, 6, 23, 16));
      expect(reset?.recoveryAttemptCount, 0);
      expect(reset?.recoveryWindowStart, isNull);
    });

    test('resetSecurityState inserts a row when none exists', () async {
      await repo.insertAccount(_makeAccount());
      await repo.resetSecurityState('admin', DateTime.utc(2026, 6, 23, 16));
      final found = await repo.getSecurityState('admin');
      expect(found?.consecutiveFailures, 0);
      expect(found?.lastSucceededAt, DateTime.utc(2026, 6, 23, 16));
    });

    // ── role / status round-trip ───────────────────────────────────────────

    test(
      'all AccountRole values survive a round-trip through the DB',
      () async {
        for (final role in AccountRole.values) {
          final id = 'acc_${role.name}';
          await repo.insertAccount(
            _makeAccount(id: id, role: role, username: '${role.name}@test'),
          );
          final found = await repo.findById(id);
          expect(found?.role, role, reason: 'role ${role.name} round-trip');
        }
      },
    );

    test(
      'all AccountStatus values survive a round-trip through the DB',
      () async {
        final accounts = [
          _makeAccount(
            id: 'a1',
            username: 'u1@t',
            status: AccountStatus.active,
          ),
          _makeAccount(
            id: 'a2',
            username: 'u2@t',
            status: AccountStatus.suspended,
          ),
          _makeAccount(
            id: 'a3',
            username: 'u3@t',
            status: AccountStatus.disabled,
          ),
        ];
        for (final acc in accounts) {
          await repo.insertAccount(acc);
          final found = await repo.findById(acc.internalId);
          expect(
            found?.status,
            acc.status,
            reason: 'status ${acc.status.name} round-trip',
          );
        }
      },
    );
  });
}
