// lib/features/dashboard/domain/entities/dashboard_metrics.dart

import 'package:equatable/equatable.dart';

/// Snapshot of the library's operational metrics.
///
/// Counts are derived from normalized schema queries defined in
/// `implementation_backlog.md` § M10.1. No Drift, database, or filesystem
/// types are referenced; the entity is persistence-agnostic.
class DashboardMetrics extends Equatable {
  const DashboardMetrics({
    required this.totalImportedFiles,
    required this.needsReview,
    required this.inProgress,
    required this.classified,
    required this.copiedToLibrary,
    required this.readyForExport,
    required this.duplicateGroups,
    required this.corruptedFiles,
    required this.totalDocuments,
  });

  /// Count of document_files where file_role_key = 'source_original'.
  final int totalImportedFiles;

  /// Count of documents where workflow_status_key = 'needs_review'.
  final int needsReview;

  /// Count of documents where workflow_status_key = 'in_progress'.
  final int inProgress;

  /// Count of documents where workflow_status_key = 'classified'.
  final int classified;

  /// Count of documents where workflow_status_key = 'copied_to_library'.
  final int copiedToLibrary;

  /// Count of documents where workflow_status_key = 'ready_for_export'.
  final int readyForExport;

  /// Count of duplicate_groups with at least 2 duplicate_group_members.
  final int duplicateGroups;

  /// Count of document_files where file_health_key = 'corrupted'.
  final int corruptedFiles;

  /// Total count of logical documents (all statuses).
  final int totalDocuments;

  /// Overall completion fraction (0.0–1.0).
  ///
  /// (copiedToLibrary + readyForExport) / totalDocuments.
  /// Returns 0.0 when totalDocuments is 0 to avoid division by zero.
  double get completionPercent {
    if (totalDocuments == 0) return 0.0;
    return (copiedToLibrary + readyForExport) / totalDocuments;
  }

  /// Classification-or-beyond fraction: docs that have been at least classified.
  double get classificationPercent {
    if (totalDocuments == 0) return 0.0;
    return (classified + copiedToLibrary + readyForExport) / totalDocuments;
  }

  /// Fraction of documents that have a verified managed copy.
  double get copiedToLibraryPercent {
    if (totalDocuments == 0) return 0.0;
    return (copiedToLibrary + readyForExport) / totalDocuments;
  }

  /// Fraction of documents ready for local export.
  double get readyForExportPercent {
    if (totalDocuments == 0) return 0.0;
    return readyForExport / totalDocuments;
  }

  static const DashboardMetrics empty = DashboardMetrics(
    totalImportedFiles: 0,
    needsReview: 0,
    inProgress: 0,
    classified: 0,
    copiedToLibrary: 0,
    readyForExport: 0,
    duplicateGroups: 0,
    corruptedFiles: 0,
    totalDocuments: 0,
  );

  @override
  List<Object?> get props => [
    totalImportedFiles,
    needsReview,
    inProgress,
    classified,
    copiedToLibrary,
    readyForExport,
    duplicateGroups,
    corruptedFiles,
    totalDocuments,
  ];
}
