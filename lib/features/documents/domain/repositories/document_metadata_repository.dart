// lib/features/documents/domain/repositories/document_metadata_repository.dart

import '../../../export/domain/entities/export_category_entry.dart';
import '../../../export/domain/entities/export_document_metadata.dart';
import '../../../export/domain/entities/export_eligibility_result.dart';
import '../../../export/domain/entities/export_keywords_result.dart';
import '../../../export/domain/entities/exportable_document_ref.dart';
import '../entities/document_aggregate.dart';
import '../entities/normalized_draft.dart';

/// Cohesive, persistence-agnostic contract for reading and writing a document's
/// metadata aggregate. Implementations keep all database-specific types inside
/// the data layer and expose only domain models. No document-deletion method is
/// exposed by design.
abstract class DocumentMetadataRepository {
  /// Loads the complete metadata aggregate for [documentId], or `null` if the
  /// document does not exist.
  Future<DocumentAggregate?> loadAggregate(int documentId);

  /// Persists a normalized draft transactionally:
  ///
  /// - updates common document metadata;
  /// - replaces the matching type-detail row and removes obsolete detail rows;
  /// - replaces primary and additional classifications;
  /// - replaces keyword links, reusing existing normalized keywords;
  /// - synchronizes the denormalized `primary_main_category_id` /
  ///   `primary_sub_category_id` with the primary classification;
  /// - sets `workflow_status_key = [workflowStatusKey]` and `updated_at = now`;
  /// - clears `classified_at` when [clearClassifiedAt] is true, otherwise leaves
  ///   the existing `classified_at` untouched.
  ///
  /// The caller (the draft-save use case) decides the workflow/timestamp values
  /// so metadata and the status decision are persisted atomically. Never touches
  /// physical files and never assigns a document code. Any failure rolls back
  /// every change. Throws [StateError] if the document is missing.
  Future<void> saveDraft(
    NormalizedDraft draft, {
    required DateTime now,
    required String workflowStatusKey,
    required bool clearClassifiedAt,
  });

  /// Transitions a validated document to `classified` transactionally: re-syncs
  /// the denormalized primary category fields from the primary classification
  /// row, sets `classified_at = now` and `updated_at = now`. Does not copy
  /// files or assign a document code. Throws [StateError] if the document is
  /// missing.
  Future<void> markClassified(int documentId, {required DateTime now});

  /// Explicitly returns a document to `in_progress` transactionally: sets
  /// `workflow_status_key = 'in_progress'`, clears `classified_at`, and sets
  /// `updated_at = now`. Only metadata/workflow fields change — no physical
  /// file is ever copied, moved, or modified, and no document code is assigned.
  /// Throws [StateError] if the document is missing. The caller (use case)
  /// enforces the `classified -> in_progress` precondition.
  Future<void> returnToInProgress(int documentId, {required DateTime now});

  /// Evaluates export eligibility for [documentId]
  /// (workflow_and_validation_spec.md §10). Loads only the fields required by
  /// the eligibility rules, not the full aggregate. Throws [StateError] if the
  /// document does not exist.
  Future<ExportEligibilityResult> checkExportEligibility(int documentId);

  /// Transitions [documentId] from `copied_to_library` to `ready_for_export`
  /// transactionally: sets `workflow_status_key = 'ready_for_export'`,
  /// `ready_for_export_at = now`, and `updated_at = now`. Throws [StateError]
  /// if the document is not currently `copied_to_library` (including a
  /// concurrent-transition race).
  Future<void> markReadyForExport(int documentId, {required DateTime now});

  /// Returns every document with `workflow_status_key = 'ready_for_export'`,
  /// ordered by `ready_for_export_at` ascending. Used by P3.3 batch
  /// generation.
  Future<List<ExportableDocumentRef>> listReadyForExport();

  /// Loads website-safe export metadata for [documentIds].
  ///
  /// Result order matches the order of [documentIds]; ids with no matching
  /// document are silently skipped.
  Future<List<ExportDocumentMetadata>> loadExportMetadata(
    List<int> documentIds,
  );

  /// Loads all active main categories and their active subcategories,
  /// ordered by sort_order.
  Future<List<ExportCategoryEntry>> loadExportCategories();

  /// Loads all keywords used by [documentIds] plus the document-keyword join
  /// data, identified by document code.
  Future<ExportKeywordsResult> loadExportKeywords(List<int> documentIds);
}
