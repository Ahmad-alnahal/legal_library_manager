import '../app_database.dart';
import 'country_seed_data.dart';

/// Seeds the initial application settings with finalized default values.
///
/// Idempotent and transactional: re-running updates the canonical values
/// without creating duplicates. The permanent copy-only policy always reseeds
/// as `true` — this seeder must never be a way to disable source-file
/// protection. Not wired into app startup; callers invoke [seedDefaults].
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
      await _upsert(defaultUiLanguageKey, 'ar', timestamp);
      // Default document country for new/manual metadata forms. This is only a
      // pre-selected default; it is never auto-applied to imported/unreviewed
      // rows, and users may change it before saving.
      await _upsert(defaultDocumentCountryKey, palestineCountryKey, timestamp);
      // Copy-only protection is permanent and always reseeds to true.
      await _upsert(copyOnlyPolicyEnabledKey, 'true', timestamp);
      await _upsert(schemaVersionKey, _db.schemaVersion.toString(), timestamp);
    });
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
