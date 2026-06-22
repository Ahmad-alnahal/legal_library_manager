// lib/features/managed_copy/domain/entities/cleanup_recovery_result.dart

/// Outcome of a recovery-artifact cleanup attempt.
enum CleanupRecoveryResult {
  /// All eligible artifacts were deleted successfully.
  cleaned,

  /// Some artifacts were deleted; others could not be removed.
  partialFailure,

  /// No eligible artifacts were successfully deleted.
  failed,

  /// No eligible artifacts were present; nothing was attempted.
  nothingToClean,
}
