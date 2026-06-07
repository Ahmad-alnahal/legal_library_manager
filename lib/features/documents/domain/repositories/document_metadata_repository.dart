// lib/features/documents/domain/repositories/document_metadata_repository.dart

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
}
