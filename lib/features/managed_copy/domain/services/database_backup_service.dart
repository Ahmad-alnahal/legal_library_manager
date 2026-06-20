// lib/features/managed_copy/domain/services/database_backup_service.dart

/// Backup boundary for the mandatory pre-copy database snapshot.
///
/// Implementations live in the data layer and use the live SQLite connection.
/// Domain and application layers depend only on this abstraction, so unit
/// tests never touch the production database.
abstract class DatabaseBackupService {
  /// Creates a consistent, verified SQLite backup inside [backupRoot].
  ///
  /// Filename format:
  ///   `legal_library_backup_yyyy-MM-dd_HHmmss_{operationId}.sqlite`
  ///
  /// Uses SQLite's online backup mechanism (VACUUM INTO) — safe while the
  /// database is open and WAL-backed. Verifies the resulting file is a
  /// readable SQLite database before returning success.
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  });
}

/// Result of a backup attempt.
sealed class BackupResult {
  const BackupResult();
}

final class BackupSuccess extends BackupResult {
  const BackupSuccess({required this.backupPath});

  /// The absolute path of the verified backup file.
  final String backupPath;
}

final class BackupFailure extends BackupResult {
  const BackupFailure({required this.safeMessage});

  /// Short, safe English description of the failure.
  final String safeMessage;
}
