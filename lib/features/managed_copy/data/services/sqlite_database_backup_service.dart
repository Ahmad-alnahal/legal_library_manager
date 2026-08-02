// lib/features/managed_copy/data/services/sqlite_database_backup_service.dart

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/services/database_backup_service.dart';

/// SQLite-backed [DatabaseBackupService].
///
/// Uses `VACUUM INTO 'path'` — SQLite's online backup mechanism. VACUUM INTO
/// creates a fully consistent copy even when WAL mode is active and the
/// database is open. No fragile file-copy of a live .sqlite / .sqlite-wal
/// pair is ever performed.
///
/// Verification opens the backup in a separate, read-only connection and runs
/// `PRAGMA quick_check`. A file that merely has a valid 16-byte header but is
/// otherwise empty or corrupt will fail this check.
class SqliteDatabaseBackupService implements DatabaseBackupService {
  const SqliteDatabaseBackupService(this._db);

  final AppDatabase _db;

  /// SQLite magic header bytes: "SQLite format 3\0" (16 bytes).
  static const List<int> _sqliteMagic = [
    83, 81, 76, 105, 116, 101, 32, // SQLite
    102, 111, 114, 109, 97, 116, 32, // format
    51, 0, // 3\0
  ];

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async {
    try {
      final String dateStr = _formatTimestamp(timestamp);
      // Sanitize operationId to filename-safe characters only.
      final String safeOpId = operationId.replaceAll(RegExp(r'[^\w_-]'), '_');
      final String filename =
          'legal_library_backup_${dateStr}_$safeOpId.sqlite';
      final String backupPath = _joinPath(backupRoot, filename);

      // VACUUM INTO cannot use bound parameters in SQLite's SQL parser, so
      // validate the path has no single quotes before embedding it. Windows
      // paths cannot legally contain single quotes, so this is a safety guard.
      if (backupPath.contains("'") || backupPath.contains('\x00')) {
        return const BackupFailure(
          safeMessage:
              "Backup folder path must not contain apostrophes or single "
              "quotes (e.g. \"Ahmad's Files\"). "
              'Please choose a different backup folder location.',
        );
      }

      if (File(backupPath).existsSync()) {
        return BackupFailure(
          safeMessage: 'Backup file already exists: $filename',
        );
      }

      // Perform the online backup. VACUUM INTO is atomic and consistent.
      await _db.customStatement("VACUUM INTO '$backupPath'");

      if (!verifyBackupFile(backupPath)) {
        try {
          File(backupPath).deleteSync();
        } catch (_) {}
        return const BackupFailure(safeMessage: 'Backup verification failed.');
      }

      _pruneOldBackups(backupRoot, keep: 3);
      return BackupSuccess(backupPath: backupPath);
    } catch (_) {
      return const BackupFailure(safeMessage: 'Backup creation failed.');
    }
  }

  /// Deletes all but the [keep] most recent owned backup files in
  /// [backupRoot]. Never touches non-owned files. Any failure here is
  /// swallowed — pruning must never fail the backup operation itself.
  void _pruneOldBackups(String backupRoot, {required int keep}) {
    try {
      final dir = Directory(backupRoot);
      if (!dir.existsSync()) return;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => _isOwnedBackup(f.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (files.length <= keep) return;
      for (final f in files.sublist(0, files.length - keep)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  bool _isOwnedBackup(String path) {
    final name = path.split(r'\').last.split('/').last;
    return name.startsWith('legal_library_backup_') && name.endsWith('.sqlite');
  }

  /// Verifies a backup file by:
  /// 1. Confirming the 16-byte SQLite magic header is present.
  /// 2. Opening the file in a separate read-only connection and running
  ///    `PRAGMA quick_check`. A header-only or corrupt file will fail this.
  ///
  /// Exposed as a non-private method so tests can verify specific file cases
  /// without going through the full backup workflow.
  static bool verifyBackupFile(String path) {
    if (!_checkHeader(path)) return false;

    Database? backupDb;
    try {
      backupDb = sqlite3.open(path, mode: OpenMode.readOnly);
      final results = backupDb.select('PRAGMA quick_check');
      if (results.isEmpty) return false;
      final value = results.first.columnAt(0);
      return value == 'ok';
    } catch (_) {
      return false;
    } finally {
      try {
        backupDb?.dispose(); // ignore: deprecated_member_use
      } catch (_) {}
    }
  }

  /// Reads the first 16 bytes and compares them to the SQLite magic header.
  static bool _checkHeader(String path) {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      if (file.lengthSync() < 100) return false;
      raf = file.openSync();
      final List<int> header = raf.readSync(16);
      if (header.length < 16) return false;
      for (int i = 0; i < 16; i++) {
        if (header[i] != _sqliteMagic[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  /// Formats [dt] as `yyyy-MM-dd_HHmmss` (UTC).
  String _formatTimestamp(DateTime dt) {
    final d = dt.toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}_'
        '${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}'
        '${d.second.toString().padLeft(2, '0')}';
  }

  String _joinPath(String base, String part) {
    final b = base.replaceAll('/', r'\');
    final trimmed = (b.length > 3 && b.endsWith(r'\'))
        ? b.substring(0, b.length - 1)
        : b;
    return '$trimmed\\$part';
  }
}
