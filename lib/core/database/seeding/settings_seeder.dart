import 'package:drift/drift.dart';

import '../app_database.dart';
import 'country_seed_data.dart';

/// Seeds the initial application settings with finalized default values.
///
/// Idempotent and transactional, and safe to run on every startup. User-owned
/// preferences ([defaultUiLanguageKey], [defaultDocumentCountryKey]) are only
/// inserted when absent, so a value the user changed survives restarts and is
/// never reset to its seed default. The permanent copy-only policy is always
/// forced back to `true` — this seeder must never be a way to disable
/// source-file protection — and [schemaVersionKey] is always updated to the
/// current schema version.
///
/// `managed_library_root` and `database_backup_root` are intentionally NOT
/// seeded: they have no safe default and must be configured by the user.
class SettingsSeeder {
  SettingsSeeder(this._db);

  final AppDatabase _db;

  /// Setting keys with finalized defaults that this seeder owns.
  static const String defaultUiLanguageKey = 'default_ui_language';
  static const String defaultDocumentCountryKey =
      'default_document_country_key';
  static const String copyOnlyPolicyEnabledKey = 'copy_only_policy_enabled';
  static const String schemaVersionKey = 'schema_version';

  Future<void> seedDefaults({DateTime? now}) {
    final String timestamp = (now ?? DateTime.now().toUtc())
        .toUtc()
        .toIso8601String();

    return _db.transaction(() async {
      // User-owned preference: only seed the initial default; never overwrite a
      // value the user has changed.
      await _insertIfAbsent(defaultUiLanguageKey, 'ar', timestamp);
      // Default document country for new/manual metadata forms. Only a
      // pre-selected initial default; it is never auto-applied to
      // imported/unreviewed rows, and a user-changed value must survive
      // restarts, so this too is insert-if-absent.
      await _insertIfAbsent(
        defaultDocumentCountryKey,
        palestineCountryKey,
        timestamp,
      );
      // Copy-only protection is permanent and is always forced back to true.
      await _upsert(copyOnlyPolicyEnabledKey, 'true', timestamp);
      // Schema version is owned by the app and always updated to current.
      await _upsert(schemaVersionKey, _db.schemaVersion.toString(), timestamp);
    });
  }

  /// Inserts the row only when [key] is not already present, leaving any
  /// user-changed value untouched.
  Future<void> _insertIfAbsent(String key, String value, String timestamp) {
    return _db
        .into(_db.settings)
        .insert(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: timestamp,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _upsert(String key, String value, String timestamp) {
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: timestamp,
          ),
        );
  }
}
