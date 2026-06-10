import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/settings_seeder.dart';

void main() {
  group('SettingsSeeder', () {
    late AppDatabase db;
    late SettingsSeeder seeder;

    setUp(() {
      db = AppDatabase.inMemory();
      seeder = SettingsSeeder(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<Map<String, String>> readSettings() async {
      final rows = await db.select(db.settings).get();
      return {for (final r in rows) r.key: r.value};
    }

    test('seeds the finalized default settings', () async {
      await seeder.seedDefaults();
      final Map<String, String> values = await readSettings();
      expect(values['default_ui_language'], 'ar');
      expect(values['default_document_country_key'], 'ps');
      expect(values['copy_only_policy_enabled'], 'true');
      expect(values['schema_version'], db.schemaVersion.toString());
      expect(values.length, 4);
    });

    test('is idempotent (no duplicates on re-run)', () async {
      await seeder.seedDefaults();
      await seeder.seedDefaults();
      expect((await db.select(db.settings).get()).length, 4);
    });

    test('preserves a user-changed default country across reseeding', () async {
      await seeder.seedDefaults();
      // The user changes their default document country.
      await (db.update(db.settings)
            ..where((s) => s.key.equals('default_document_country_key')))
          .write(const SettingsCompanion(value: Value('jo')));
      expect((await readSettings())['default_document_country_key'], 'jo');

      // Reseeding (e.g. on the next startup) must NOT reset it to Palestine.
      await seeder.seedDefaults();
      expect((await readSettings())['default_document_country_key'], 'jo');
      expect((await db.select(db.settings).get()).length, 4);
    });

    test(
      'preserves a user-changed default UI language across reseeding',
      () async {
        await seeder.seedDefaults();
        await (db.update(db.settings)
              ..where((s) => s.key.equals('default_ui_language')))
            .write(const SettingsCompanion(value: Value('en')));

        await seeder.seedDefaults();
        expect((await readSettings())['default_ui_language'], 'en');
      },
    );

    test(
      'always updates schema_version to the current schema version',
      () async {
        await seeder.seedDefaults();
        // Simulate a stale schema_version from an older app version.
        await (db.update(db.settings)
              ..where((s) => s.key.equals('schema_version')))
            .write(const SettingsCompanion(value: Value('0')));

        await seeder.seedDefaults();
        expect(
          (await readSettings())['schema_version'],
          db.schemaVersion.toString(),
        );
      },
    );

    test('always restores copy_only_policy_enabled to true', () async {
      await seeder.seedDefaults();
      // Simulate tampering with the policy value.
      await (db.update(db.settings)
            ..where((s) => s.key.equals('copy_only_policy_enabled')))
          .write(const SettingsCompanion(value: Value('false')));
      expect((await readSettings())['copy_only_policy_enabled'], 'false');

      await seeder.seedDefaults();
      expect((await readSettings())['copy_only_policy_enabled'], 'true');
      expect((await db.select(db.settings).get()).length, 4);
    });

    test('library/backup roots remain absent until configured', () async {
      await seeder.seedDefaults();
      final Map<String, String> values = await readSettings();
      expect(values.containsKey('managed_library_root'), isFalse);
      expect(values.containsKey('database_backup_root'), isFalse);
    });
  });
}
