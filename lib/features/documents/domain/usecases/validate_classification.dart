// lib/features/documents/domain/usecases/validate_classification.dart

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/time/clock.dart';
import '../../../../core/validation/validation_result.dart';
import '../../../reference/domain/repositories/reference_repository.dart';
import '../entities/document_aggregate.dart';
import '../entities/document_type_details.dart';
import '../entities/draft_save_input.dart';
import '../validation/document_field_validator.dart';
import '../validation/metadata_normalizer.dart';
import '../validation/reference_validator.dart';

/// Validates whether a persisted document aggregate satisfies all
/// classification-approval requirements (workflow_and_validation_spec.md §5).
///
/// Returns structured errors; an empty result means the document may be
/// approved. Does not mutate anything.
class ValidateClassification {
  ValidateClassification({required this.references, required this.clock});

  final ReferenceRepository references;
  final Clock clock;

  Future<ValidationResult> call(DocumentAggregate agg) async {
    final ValidationErrorBuilder errors = ValidationErrorBuilder();
    final ActiveReferenceData data = await ActiveReferenceData.load(references);
    final c = agg.common;

    // Field-level validation (length/control chars, year range via the clock,
    // ISO dates, constrained detail keys, keyword validity, duplicate
    // classifications) is enforced against the persisted aggregate too, reusing
    // the same normalizer/validator as draft save.
    final normalized = MetadataNormalizer.normalize(
      DraftSaveInput(
        documentId: agg.documentId,
        common: agg.common,
        details: agg.details,
        primaryClassification: agg.primaryClassification,
        additionalClassifications: agg.additionalClassifications,
        keywords: agg.keywords,
      ),
    );
    errors.addAll(DocumentFieldValidator(clock).validate(normalized).errors);

    // Required common fields.
    _require(errors, 'documentTypeId', c.documentTypeId != null);
    _requireText(errors, 'title', c.title);
    _requireText(errors, 'languageKey', c.languageKey);
    _requireText(errors, 'trustLevelKey', c.trustLevelKey);
    _requireText(errors, 'usageRightsKey', c.usageRightsKey);
    _requireText(errors, 'metadataQualityKey', c.metadataQualityKey);

    // References that are set must be active; subcategories must belong.
    ReferenceChecks.commonReferences(c, data, errors);
    ReferenceChecks.classifications(
      agg.primaryClassification,
      agg.additionalClassifications,
      data,
      errors,
    );
    ReferenceChecks.detailMatchesType(
      c.documentTypeId,
      agg.details,
      data,
      errors,
    );

    // Primary classification, with subcategory required when the chosen main
    // category has active subcategories.
    final primary = agg.primaryClassification;
    if (primary == null) {
      _require(errors, 'primaryClassification', false);
    } else if (data.mainHasActiveSubcategories(primary.mainCategoryId) &&
        primary.subCategoryId == null) {
      errors.add(
        'primaryClassification.subCategoryId',
        'required',
        'A subcategory is required for this main category.',
      );
    }

    // Type-specific requirements.
    final String? typeKey = c.documentTypeId == null
        ? null
        : data.documentTypeKeyById[c.documentTypeId];
    _validateTypeSpecific(typeKey, agg, errors);

    // At least one acceptable file.
    if (!_hasAcceptableFile(agg)) {
      errors.add(
        'files',
        'no_acceptable_file',
        'A healthy source PDF or an approved healthy converted PDF is required.',
      );
    }

    return errors.build();
  }

  void _validateTypeSpecific(
    String? typeKey,
    DocumentAggregate agg,
    ValidationErrorBuilder errors,
  ) {
    final details = agg.details;
    switch (typeKey) {
      case null:
        return; // documentType already reported as required.
      case 'book':
        final author = details is BookDetailsData ? details.author : null;
        _requireText(errors, 'book.author', author);
      case 'thesis':
        final t = details is ThesisDetailsData ? details : null;
        _requireText(errors, 'thesis.researcherName', t?.researcherName);
        _requireText(errors, 'thesis.degreeTypeKey', t?.degreeTypeKey);
        _requireText(errors, 'thesis.universityName', t?.universityName);
      case 'research_paper':
        final r = details is ResearchDetailsData ? details : null;
        if (!_present(r?.researcherName) && !_present(r?.publishingEntity)) {
          errors.add(
            'research',
            'required',
            'Researcher name or publishing entity is required.',
          );
        }
      case 'legislation':
        final l = details is LegislationDetailsData ? details : null;
        _requireText(
          errors,
          'legislation.legislationTypeKey',
          l?.legislationTypeKey,
        );
        _requireText(errors, 'countryKey', agg.common.countryKey);
        if (agg.common.publicationYear == null &&
            !_present(l?.publicationDate)) {
          errors.add(
            'legislation',
            'required',
            'Publication year or publication date is required.',
          );
        }
      case 'court_precedent':
        final cc = details is CourtCaseDetailsData ? details : null;
        _requireText(errors, 'courtCase.courtName', cc?.courtName);
        _requireText(errors, 'courtCase.caseNumber', cc?.caseNumber);
        _requireText(errors, 'countryKey', agg.common.countryKey);
        if (!_present(cc?.judgmentResult) && !_present(cc?.legalPrinciple)) {
          errors.add(
            'courtCase',
            'required',
            'Judgment result or legal principle is required.',
          );
        }
      case 'institutional_report':
        final rep = details is ReportDetailsData ? details : null;
        _requireText(errors, 'report.publishingEntity', rep?.publishingEntity);
      case 'other':
        _requireText(errors, 'title', agg.common.title);
        _requireText(errors, 'reviewNotes', agg.common.reviewNotes);
      default:
        return;
    }
  }

  /// True if the document has a healthy `source_original`, or a healthy
  /// `converted_pdf` whose conversion is approved.
  bool _hasAcceptableFile(DocumentAggregate agg) {
    final bool hasHealthySource = agg.files.any(
      (f) =>
          f.fileRoleKey == FileRoleKey.sourceOriginal &&
          f.fileHealthKey == FileHealthKey.healthy,
    );
    if (hasHealthySource) return true;

    final Set<int> approvedOutputs = {
      for (final conv in agg.conversions)
        if (conv.outputFileId != null && conv.isApproved) conv.outputFileId!,
    };
    return agg.files.any(
      (f) =>
          f.fileRoleKey == FileRoleKey.convertedPdf &&
          f.fileHealthKey == FileHealthKey.healthy &&
          approvedOutputs.contains(f.id),
    );
  }

  static bool _present(String? v) => v != null && v.trim().isNotEmpty;

  void _require(ValidationErrorBuilder errors, String field, bool ok) {
    if (!ok) errors.add(field, 'required', 'This field is required.');
  }

  void _requireText(
    ValidationErrorBuilder errors,
    String field,
    String? value,
  ) {
    if (!_present(value)) {
      errors.add(field, 'required', 'This field is required.');
    }
  }
}
