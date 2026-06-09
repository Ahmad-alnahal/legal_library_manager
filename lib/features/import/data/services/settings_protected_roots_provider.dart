// lib/features/import/data/services/settings_protected_roots_provider.dart

import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../application/protected_roots_provider.dart';
import '../../domain/entities/protected_roots.dart';

/// Builds [ProtectedRoots] from the real application-support directory (where the
/// SQLite database lives) plus the optional `managed_library_root` and
/// `database_backup_root` settings. No default managed-library/backup paths are
/// invented: unset settings stay null.
class SettingsProtectedRootsProvider implements ProtectedRootsProvider {
  SettingsProtectedRootsProvider(this._db);

  final AppDatabase _db;

  static const String _managedLibraryKey = 'managed_library_root';
  static const String _backupKey = 'database_backup_root';

  @override
  Future<ProtectedRoots> load() async {
    final String databaseRoot = (await getApplicationSupportDirectory()).path;
    final String? managedLibraryRoot = await _setting(_managedLibraryKey);
    final String? backupRoot = await _setting(_backupKey);
    return ProtectedRoots(
      databaseRoot: databaseRoot,
      managedLibraryRoot: managedLibraryRoot,
      backupRoot: backupRoot,
    );
  }

  Future<String?> _setting(String key) async {
    final Setting? row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    final String? value = row?.value;
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }
}
