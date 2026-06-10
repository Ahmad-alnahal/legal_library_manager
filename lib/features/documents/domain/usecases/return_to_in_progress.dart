// lib/features/documents/domain/usecases/return_to_in_progress.dart

import '../../../../core/time/clock.dart';
import '../../../../core/validation/validation_error.dart';
import '../../../../core/validation/validation_result.dart';
import '../entities/document_aggregate.dart';
import '../repositories/document_metadata_repository.dart';

/// Explicit "return to in_progress" use case
/// (workflow_and_validation_spec.md §5: `classified -> in_progress`).
///
/// Reopens a `classified` document for further editing. The transition is
/// deliberate and user-initiated; it only updates metadata/workflow fields
/// (sets `in_progress`, clears `classified_at`) transactionally and never
/// copies, moves, or modifies any source or managed file.
///
/// Returns a valid result on success, or a structured error:
/// - `not_found` when the document does not exist;
/// - `invalid_status` when the document is not currently `classified`.
class ReturnToInProgress {
  ReturnToInProgress({required this.repository, required this.clock});

  final DocumentMetadataRepository repository;
  final Clock clock;

  Future<ValidationResult> call(int documentId) async {
    final DocumentAggregate? agg = await repository.loadAggregate(documentId);
    if (agg == null) {
      return ValidationResult([
        ValidationError(
          field: 'document',
          code: 'not_found',
          message: 'Document $documentId does not exist.',
        ),
      ]);
    }
    if (agg.workflowStatusKey != 'classified') {
      return ValidationResult([
        ValidationError(
          field: 'workflowStatus',
          code: 'invalid_status',
          message: 'Only a classified document can be returned to in_progress.',
        ),
      ]);
    }

    await repository.returnToInProgress(documentId, now: clock.nowUtc());
    return const ValidationResult.valid();
  }
}
