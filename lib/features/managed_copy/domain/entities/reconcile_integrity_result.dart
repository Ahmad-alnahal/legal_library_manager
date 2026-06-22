// lib/features/managed_copy/domain/entities/reconcile_integrity_result.dart

/// Summary of a bulk managed-copy integrity reconciliation.
///
/// Counts are per managed-copy file record, except [downgradedDocumentCount]
/// which counts documents whose workflow status was moved back to classified.
/// Source files are never inspected or counted here.
class ReconcileIntegrityResult {
  const ReconcileIntegrityResult({
    required this.healthyCount,
    required this.missingCount,
    required this.corruptedCount,
    required this.restoredCount,
    required this.downgradedDocumentCount,
    required this.failedCount,
  });

  static const empty = ReconcileIntegrityResult(
    healthyCount: 0,
    missingCount: 0,
    corruptedCount: 0,
    restoredCount: 0,
    downgradedDocumentCount: 0,
    failedCount: 0,
  );

  /// Files that are physically present on disk and match stored size + hash.
  final int healthyCount;

  /// Files newly marked as missing (previously healthy or corrupted, now absent).
  final int missingCount;

  /// Files newly marked as corrupted (present on disk but size or hash differs).
  final int corruptedCount;

  /// Files restored from a previously-missing or corrupted state after their
  /// content was verified to match stored metadata.
  final int restoredCount;

  /// Documents whose workflow status was moved from copied_to_library to
  /// classified because they have no remaining healthy managed copy.
  final int downgradedDocumentCount;

  /// Files whose health check could not be completed due to a filesystem or
  /// database error. Health status is unchanged for these files.
  final int failedCount;

  bool get hasIssues =>
      missingCount > 0 || corruptedCount > 0 || failedCount > 0;

  bool get isClean => !hasIssues;

  int get totalChecked =>
      healthyCount +
      missingCount +
      corruptedCount +
      restoredCount +
      failedCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReconcileIntegrityResult &&
          healthyCount == other.healthyCount &&
          missingCount == other.missingCount &&
          corruptedCount == other.corruptedCount &&
          restoredCount == other.restoredCount &&
          downgradedDocumentCount == other.downgradedDocumentCount &&
          failedCount == other.failedCount;

  @override
  int get hashCode => Object.hash(
    healthyCount,
    missingCount,
    corruptedCount,
    restoredCount,
    downgradedDocumentCount,
    failedCount,
  );
}
