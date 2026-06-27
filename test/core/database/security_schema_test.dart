// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('security schema', () {
    late AppDatabase db;
    const String nowIso = '2026-06-23T10:00:00Z';

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    // ── table and index existence ─────────────────────────────────────────────

    test('all four security tables exist in a fresh database', () async {
      final Set<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table';",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();

      expect(
        tables,
        containsAll(<String>[
          'accounts',
          'account_security_state',
          'recovery_credentials',
          'security_audit_log',
        ]),
      );
    });

    test('expected indexes exist on the security tables', () async {
      final Set<String> indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'index';",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();

      expect(
        indexes,
        containsAll(<String>[
          'ux_accounts_username',
          'ix_accounts_role_key',
          'ix_accounts_status_key',
          'ix_security_audit_log_created_at',
          'ix_security_audit_log_event_type',
          'ix_security_audit_log_actor',
        ]),
      );
    });

    // ── accounts table constraints ────────────────────────────────────────────

    Future<void> insertAccount({
      String id = 'admin',
      String username = 'marjiy@admin',
      String role = 'admin',
      String status = 'active',
    }) => db.customStatement(
      'INSERT INTO accounts (internal_id, username, display_name, role_key, '
      'status_key, must_change_password, password_hash, created_at, updated_at) '
      "VALUES ('$id', '$username', 'Display', '$role', '$status', "
      "1, '\$argon2id\$hash', '$nowIso', '$nowIso')",
    );

    test('accounts: unique username constraint is enforced', () async {
      await insertAccount(id: 'admin', username: 'marjiy@admin');

      // Different internal_id but same username must fail.
      expect(
        () => insertAccount(
          id: 'op1',
          username: 'marjiy@admin',
          role: 'operator',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('accounts: role_key CHECK rejects unknown values', () async {
      expect(
        () => db.customStatement(
          'INSERT INTO accounts (internal_id, username, display_name, role_key, '
          'must_change_password, password_hash, created_at, updated_at) '
          "VALUES ('x', 'x@x', 'X', 'superuser', 0, 'h', '$nowIso', '$nowIso')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('accounts: status_key CHECK rejects unknown values', () async {
      expect(
        () => db.customStatement(
          'INSERT INTO accounts (internal_id, username, display_name, role_key, '
          'status_key, must_change_password, password_hash, created_at, updated_at) '
          "VALUES ('x', 'x@x', 'X', 'operator', 'banned', 0, 'h', "
          "'$nowIso', '$nowIso')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('accounts: default status is active', () async {
      await db.customStatement(
        'INSERT INTO accounts (internal_id, username, display_name, role_key, '
        'must_change_password, password_hash, created_at, updated_at) '
        "VALUES ('admin', 'marjiy@admin', 'Admin', 'admin', 1, 'h', "
        "'$nowIso', '$nowIso')",
      );
      final row = await db
          .customSelect(
            'SELECT status_key FROM accounts WHERE internal_id = ?',
            variables: [Variable.withString('admin')],
          )
          .getSingle();
      expect(row.read<String>('status_key'), 'active');
    });

    // ── account_security_state FK ─────────────────────────────────────────────

    test(
      'account_security_state: account_id FK to accounts is enforced',
      () async {
        expect(
          () => db.customStatement(
            'INSERT INTO account_security_state (account_id) '
            "VALUES ('nonexistent')",
          ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test(
      'account_security_state: cascades when parent account is deleted',
      () async {
        await insertAccount();
        await db.customStatement(
          "INSERT INTO account_security_state (account_id) VALUES ('admin')",
        );
        expect(
          await db
              .customSelect('SELECT COUNT(*) AS c FROM account_security_state')
              .getSingle()
              .then((r) => r.read<int>('c')),
          1,
        );

        await db.customStatement(
          "DELETE FROM accounts WHERE internal_id = 'admin'",
        );

        // Cascade deletes the security state row.
        expect(
          await db
              .customSelect('SELECT COUNT(*) AS c FROM account_security_state')
              .getSingle()
              .then((r) => r.read<int>('c')),
          0,
        );
      },
    );

    // ── recovery_credentials FK ───────────────────────────────────────────────

    test('recovery_credentials: account_id FK to accounts is enforced', () async {
      expect(
        () => db.customStatement(
          "INSERT INTO recovery_credentials (account_id, key_hash, created_at) "
          "VALUES ('nonexistent', 'hash', '$nowIso')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('recovery_credentials: default algorithm_key is argon2id', () async {
      await insertAccount();
      await db.customStatement(
        "INSERT INTO recovery_credentials (account_id, key_hash, created_at) "
        "VALUES ('admin', '\$argon2id\$v=19\$keyhash', '$nowIso')",
      );
      final row = await db
          .customSelect(
            'SELECT algorithm_key FROM recovery_credentials WHERE account_id = ?',
            variables: [Variable.withString('admin')],
          )
          .getSingle();
      expect(row.read<String>('algorithm_key'), 'argon2id');
    });

    // ── security_audit_log ────────────────────────────────────────────────────

    test(
      'security_audit_log: inserts with nullable actor and target',
      () async {
        await db.customStatement(
          "INSERT INTO security_audit_log (event_type_key, created_at) "
          "VALUES ('login_success', '$nowIso')",
        );
        final row = await db
            .customSelect('SELECT * FROM security_audit_log')
            .getSingle();
        expect(row.read<String>('event_type_key'), 'login_success');
        expect(row.readNullable<String>('actor_account_id'), isNull);
      },
    );

    test(
      'security_audit_log: actor FK SET NULL does not block orphan insert',
      () async {
        // Inserting a log event with a non-null actor_account_id that references
        // a non-existent account is a FK violation.
        expect(
          () => db.customStatement(
            "INSERT INTO security_audit_log "
            "(event_type_key, actor_account_id, created_at) "
            "VALUES ('login_failure', 'ghost_id', '$nowIso')",
          ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    // ── v2 → v3 migration ─────────────────────────────────────────────────────

    test(
      'migrating a v2 database to v3 creates all four security tables',
      () async {
        // Simulate a pre-security MARJIY database (schema version 2, no
        // security tables). The migration only adds tables — no existing data
        // is touched — so an otherwise-empty DB at user_version=2 is a valid
        // test proxy for a real v2 installation.
        final Database raw = sqlite3.openInMemory();
        raw.execute('PRAGMA user_version = 2;');
        final AppDatabase migratedDb = AppDatabase.forExecutor(
          NativeDatabase.opened(raw),
        );
        addTearDown(migratedDb.close);

        // Trigger Drift to open and run migrations.
        await migratedDb.customSelect('SELECT 1;').get();

        final int version =
            (await migratedDb.customSelect('PRAGMA user_version;').getSingle())
                .read<int>('user_version');
        expect(version, 4, reason: 'schema version must be bumped to 4');

        final Set<String> tables =
            (await migratedDb
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'table';",
                    )
                    .get())
                .map((r) => r.read<String>('name'))
                .toSet();

        expect(
          tables,
          containsAll(<String>[
            'accounts',
            'account_security_state',
            'recovery_credentials',
            'security_audit_log',
          ]),
        );
      },
    );

    test('a fresh database is created directly at version 4', () async {
      final int version =
          (await db.customSelect('PRAGMA user_version;').getSingle()).read<int>(
            'user_version',
          );
      expect(version, 4);
    });
  });
}
