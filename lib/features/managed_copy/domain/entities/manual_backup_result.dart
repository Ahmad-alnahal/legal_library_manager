// lib/features/managed_copy/domain/entities/manual_backup_result.dart

/// Result of a manual database backup attempt.
///
/// The backup covers app database records only — never original source files,
/// managed PDFs, exports, logs, or temp files.
sealed class ManualBackupResult {
  const ManualBackupResult();
}

/// The backup was created and verified successfully.
final class ManualBackupSuccess extends ManualBackupResult {
  const ManualBackupSuccess({required this.backupPath});

  /// Absolute path of the verified backup file inside the backup root.
  final String backupPath;
}

/// The backup could not be created.
final class ManualBackupFailure extends ManualBackupResult {
  const ManualBackupFailure({required this.messageKey});

  /// Short key mapped to an Arabic l10n string in the presentation layer.
  ///
  /// Values:
  /// - `'not_configured'` — backup root is not set in settings.
  /// - `'root_missing'`   — backup root is configured but the directory is absent.
  /// - `'failed'`         — the backup service returned an error.
  final String messageKey;
}
