// lib/features/managed_copy/domain/entities/recovery_artifact_summary.dart

/// Typed summary of startup recovery artifacts, grouped by cleanup eligibility.
class RecoveryArtifactSummary {
  const RecoveryArtifactSummary({
    this.copyingFiles = const [],
    this.unregisteredFinalPdfs = const [],
    this.incompleteBackups = const [],
  });

  /// Strict MARJIY `.copying` temp files directly inside the managed files dir.
  /// Eligible for safe automatic cleanup.
  final List<String> copyingFiles;

  /// Final managed PDFs (`DOC-NNNNNNN.pdf`) not registered in the database.
  /// Require manual review — never deleted automatically.
  final List<String> unregisteredFinalPdfs;

  /// Strict MARJIY backup files under 100 bytes directly inside the backup root.
  /// Eligible for safe automatic cleanup.
  final List<String> incompleteBackups;

  bool get hasEligibleForCleanup =>
      copyingFiles.isNotEmpty || incompleteBackups.isNotEmpty;

  bool get hasManualReviewRequired => unregisteredFinalPdfs.isNotEmpty;

  int get totalCount =>
      copyingFiles.length +
      unregisteredFinalPdfs.length +
      incompleteBackups.length;
}
