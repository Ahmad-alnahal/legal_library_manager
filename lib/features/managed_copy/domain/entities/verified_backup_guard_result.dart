// lib/features/managed_copy/domain/entities/verified_backup_guard_result.dart

/// Result returned by [RunWithVerifiedBackup.call].
///
/// Generic over [T] — the value produced by the guarded operation on success.
/// All pre-check failures carry no file paths; file path is only present on
/// the two post-backup outcomes.
sealed class VerifiedBackupGuardResult<T> {
  const VerifiedBackupGuardResult();
}

/// The backup root is not configured in settings.
///
/// The guarded operation was not started.
final class GuardBackupNotConfigured<T> extends VerifiedBackupGuardResult<T> {
  const GuardBackupNotConfigured();
}

/// The backup root is configured but the directory is absent on disk.
///
/// The guarded operation was not started.
final class GuardBackupRootMissing<T> extends VerifiedBackupGuardResult<T> {
  const GuardBackupRootMissing();
}

/// The backup service returned a failure.
///
/// The guarded operation was not started. A `backup_created / failed` audit
/// event has been recorded.
final class GuardBackupFailed<T> extends VerifiedBackupGuardResult<T> {
  const GuardBackupFailed();
}

/// The backup succeeded and the guarded operation completed without error.
final class GuardOperationSucceeded<T> extends VerifiedBackupGuardResult<T> {
  const GuardOperationSucceeded({
    required this.value,
    required this.backupPath,
  });

  /// The value returned by the guarded operation.
  final T value;

  /// Absolute path of the verified backup file inside the backup root.
  final String backupPath;
}

/// The backup succeeded but the guarded operation threw an exception.
///
/// The `backup_created / succeeded` audit event was recorded before the
/// operation ran. The backup is intact; only the operation failed.
final class GuardOperationFailed<T> extends VerifiedBackupGuardResult<T> {
  const GuardOperationFailed({required this.error, required this.backupPath});

  /// The exception thrown by the guarded operation.
  ///
  /// Treat as opaque in the presentation layer — show a generic Arabic error
  /// message rather than exposing raw exception text.
  final Object error;

  /// Absolute path of the verified backup file (backup succeeded before the
  /// operation ran).
  final String backupPath;
}
