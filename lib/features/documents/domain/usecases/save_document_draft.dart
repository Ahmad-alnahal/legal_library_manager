// lib/features/documents/domain/usecases/save_document_draft.dart

import '../../../../core/time/clock.dart';
import '../../../../core/validation/validation_error.dart';
import '../../../../core/validation/validation_result.dart';
import '../../../reference/domain/repositories/reference_repository.dart';
import '../entities/document_aggregate.dart';
import '../entities/draft_save_input.dart';
import '../entities/keyword_input.dart';
import '../entities/normalized_draft.dart';
import '../repositories/document_metadata_repository.dart';
import '../validation/document_field_validator.dart';
import '../validation/metadata_normalizer.dart';
import '../validation/reference_validator.dart';
import 'validate_classification.dart';

/// Transactional draft-save use case (workflow_and_validation_spec.md §5).
///
/// Permits incomplete metadata but rejects malformed entered values and invalid
/// references. Workflow handling (spec "Editing a Classified Document"):
///
/// - Saving a non-classified document (imported/needs_review/in_progress) leaves
///   it `in_progress`.
/// - Editing a `classified` document keeps it `classified` (preserving its
///   `classified_at`) when the prospective saved aggregate still passes the full
///   approval rules, otherwise returns it to `in_progress` and clears
///   `classified_at`.
///
/// The decision uses the prospective normalized metadata plus the document's
/// existing files/conversions, and is persisted atomically with the metadata.
/// Never touches physical files and never assigns a document code.
class SaveDocumentDraft {
  SaveDocumentDraft({
    required this.repository,
    required this.references,
    required this.classificationValidator,
    required this.clock,
  });

  final DocumentMetadataRepository repository;
  final ReferenceRepository references;
  final ValidateClassification classificationValidator;
  final Clock clock;

  /// Validates and saves [input]. Returns a valid result on success, or the
  /// structured errors that prevented saving (in which case nothing is written).
  Future<ValidationResult> call(DraftSaveInput input) async {
    final NormalizedDraft draft = MetadataNormalizer.normalize(input);

    final ValidationErrorBuilder errors = ValidationErrorBuilder()
      ..addAll(DocumentFieldValidator(clock).validate(draft).errors);

    final ActiveReferenceData data = await ActiveReferenceData.load(references);
    ReferenceChecks.commonReferences(draft.common, data, errors);
    ReferenceChecks.classifications(
      draft.primaryClassification,
      draft.additionalClassifications,
      data,
      errors,
    );
    ReferenceChecks.detailMatchesType(
      draft.common.documentTypeId,
      draft.details,
      data,
      errors,
    );

    final ValidationResult result = errors.build();
    if (result.isInvalid) return result;

    final DocumentAggregate? existing = await repository.loadAggregate(
      draft.documentId,
    );
    if (existing == null) {
      return ValidationResult([
        ValidationError(
          field: 'document',
          code: 'not_found',
          message: 'Document ${draft.documentId} does not exist.',
        ),
      ]);
    }

    // Decide the resulting workflow status. Only an already-classified document
    // can stay classified across an edit; everything else becomes in_progress.
    String workflowStatusKey = 'in_progress';
    bool clearClassifiedAt = true;
    if (existing.workflowStatusKey == 'classified') {
      final ValidationResult approval = await classificationValidator(
        _prospectiveAggregate(draft, existing),
      );
      if (approval.isValid) {
        workflowStatusKey = 'classified';
        clearClassifiedAt = false; // preserve existing classified_at
      }
    }

    await repository.saveDraft(
      draft,
      now: clock.nowUtc(),
      workflowStatusKey: workflowStatusKey,
      clearClassifiedAt: clearClassifiedAt,
    );
    return const ValidationResult.valid();
  }

  /// Builds the aggregate that *would* result from this save (prospective
  /// metadata + the document's existing files/conversions) for the approval
  /// re-check on a classified document.
  DocumentAggregate _prospectiveAggregate(
    NormalizedDraft draft,
    DocumentAggregate existing,
  ) {
    return DocumentAggregate(
      documentId: draft.documentId,
      workflowStatusKey: existing.workflowStatusKey,
      common: draft.common,
      details: draft.details,
      primaryClassification: draft.primaryClassification,
      additionalClassifications: draft.additionalClassifications,
      keywords: draft.keywords
          .map(
            (k) => KeywordInput(
              displayValue: k.displayValue,
              languageKey: k.languageKey,
            ),
          )
          .toList(),
      files: existing.files,
      conversions: existing.conversions,
      documentCode: existing.documentCode,
      classifiedAt: existing.classifiedAt,
    );
  }
}
