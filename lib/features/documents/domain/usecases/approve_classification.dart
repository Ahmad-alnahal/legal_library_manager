// lib/features/documents/domain/usecases/approve_classification.dart

import '../../../../core/time/clock.dart';
import '../../../../core/validation/validation_error.dart';
import '../../../../core/validation/validation_result.dart';
import '../entities/document_aggregate.dart';
import '../repositories/document_metadata_repository.dart';
import 'validate_classification.dart';

/// Approve-classification use case (workflow_and_validation_spec.md §5).
///
/// Loads the full persisted aggregate, validates it, and—only when valid—
/// transitions it to `classified` with UTC timestamps in one transaction. On
/// invalid input nothing is changed. Never copies files, assigns document
/// codes, or writes file events.
class ApproveClassification {
  ApproveClassification({
    required this.repository,
    required this.validator,
    required this.clock,
  });

  final DocumentMetadataRepository repository;
  final ValidateClassification validator;
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

    final ValidationResult result = await validator(agg);
    if (result.isInvalid) return result;

    await repository.markClassified(documentId, now: clock.nowUtc());
    return const ValidationResult.valid();
  }
}
