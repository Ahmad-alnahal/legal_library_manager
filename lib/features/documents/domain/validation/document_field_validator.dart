// lib/features/documents/domain/validation/document_field_validator.dart

import '../../../../core/time/clock.dart';
import '../../../../core/validation/field_limits.dart';
import '../../../../core/validation/text_normalizer.dart';
import '../../../../core/validation/validation_result.dart';
import '../entities/document_classification_input.dart';
import '../entities/document_type_details.dart';
import '../entities/normalized_draft.dart';

/// Allowed constrained detail-key values, mirrored from the schema CHECKs so
/// invalid keys are reported as structured errors instead of raw SQLite
/// failures.
const Set<String> _degreeTypeKeys = {'masters', 'doctorate', 'other'};
const Set<String> _legislationTypeKeys = {
  'ordinary_legislation',
  'regulation',
  'executive_regulation',
  'other',
};
const Set<String> _effectiveStatusKeys = {
  'active',
  'repealed',
  'amended',
  'expired',
  'unknown',
};

/// Pure, persistence-independent field-level validation for a normalized draft
/// (workflow_and_validation_spec.md §14). Does not check reference existence or
/// cross-table membership that requires the database — those live in the
/// use cases. Reads the current year from an injected [Clock].
class DocumentFieldValidator {
  const DocumentFieldValidator(this._clock);

  final Clock _clock;

  ValidationResult validate(NormalizedDraft draft) {
    final ValidationErrorBuilder errors = ValidationErrorBuilder();

    _validateCommon(draft, errors);
    _validateDetails(draft.details, errors);
    _validateKeywords(draft, errors);
    _validateClassificationShape(draft, errors);

    return errors.build();
  }

  void _validateCommon(NormalizedDraft draft, ValidationErrorBuilder errors) {
    final c = draft.common;
    _name(errors, 'title', c.title);
    _notes(errors, 'summary', c.summary);
    _notes(errors, 'sourceDescription', c.sourceDescription);
    _notes(errors, 'reviewNotes', c.reviewNotes);

    final int? year = c.publicationYear;
    if (year != null) {
      final int maxYear = _clock.currentYear + 1;
      if (year < FieldLimits.minPublicationYear || year > maxYear) {
        errors.add(
          'publicationYear',
          'out_of_range',
          'Publication year must be between '
              '${FieldLimits.minPublicationYear} and $maxYear.',
        );
      }
    }
  }

  void _validateDetails(
    DocumentTypeDetails? details,
    ValidationErrorBuilder errors,
  ) {
    switch (details) {
      case null:
        return;
      case BookDetailsData():
        _name(errors, 'book.author', details.author);
        _name(errors, 'book.publisher', details.publisher);
        _name(errors, 'book.publicationPlace', details.publicationPlace);
      case ThesisDetailsData():
        _name(errors, 'thesis.researcherName', details.researcherName);
        _name(errors, 'thesis.universityName', details.universityName);
        _name(errors, 'thesis.supervisorName', details.supervisorName);
        _constrained(
          errors,
          'thesis.degreeTypeKey',
          details.degreeTypeKey,
          _degreeTypeKeys,
        );
      case ResearchDetailsData():
        _name(errors, 'research.researcherName', details.researcherName);
        _name(errors, 'research.journalName', details.journalName);
        _name(errors, 'research.publishingEntity', details.publishingEntity);
        _name(errors, 'research.volume', details.volume);
        _name(errors, 'research.issue', details.issue);
      case LegislationDetailsData():
        _name(errors, 'legislation.issueNumber', details.issueNumber);
        _constrained(
          errors,
          'legislation.legislationTypeKey',
          details.legislationTypeKey,
          _legislationTypeKeys,
        );
        _name(
          errors,
          'legislation.legislationTypeOther',
          details.legislationTypeOther,
        );
        if (details.legislationTypeKey == 'other' &&
            (details.legislationTypeOther?.trim().isEmpty ?? true)) {
          errors.add(
            'legislation.legislationTypeOther',
            'required',
            'Other legislation type is required.',
          );
        }
        _constrained(
          errors,
          'legislation.effectiveStatusKey',
          details.effectiveStatusKey,
          _effectiveStatusKeys,
        );
        _isoDate(
          errors,
          'legislation.publicationDate',
          details.publicationDate,
        );
        _name(
          errors,
          'legislation.legislationNumber',
          details.legislationNumber,
        );
        if (details.legislationYear != null) {
          final int maxYear = _clock.currentYear + 1;
          if (details.legislationYear! < FieldLimits.minPublicationYear ||
              details.legislationYear! > maxYear) {
            errors.add(
              'legislation.legislationYear',
              'out_of_range',
              'Legislation year must be between '
                  '${FieldLimits.minPublicationYear} and $maxYear.',
            );
          }
        }
        _isoDate(errors, 'legislation.effectiveDate', details.effectiveDate);
        _isoDate(errors, 'legislation.repealDate', details.repealDate);
      case CourtCaseDetailsData():
        _name(errors, 'courtCase.courtName', details.courtName);
        _name(errors, 'courtCase.caseNumber', details.caseNumber);
        _name(errors, 'courtCase.judgmentResult', details.judgmentResult);
        _notes(errors, 'courtCase.legalPrinciple', details.legalPrinciple);
        _isoDate(errors, 'courtCase.judgmentDate', details.judgmentDate);
      case ReportDetailsData():
        _name(errors, 'report.publishingEntity', details.publishingEntity);
    }
  }

  void _validateKeywords(NormalizedDraft draft, ValidationErrorBuilder errors) {
    for (int i = 0; i < draft.keywords.length; i++) {
      final k = draft.keywords[i];
      final String field = 'keywords[$i]';
      if (k.normalizedValue.isEmpty || k.displayValue.isEmpty) {
        errors.add(field, 'blank', 'Keyword must not be blank.');
        continue;
      }
      if (k.displayValue.length > FieldLimits.keyword ||
          k.normalizedValue.length > FieldLimits.keyword) {
        errors.add(
          field,
          'too_long',
          'Keyword must be at most ${FieldLimits.keyword} characters.',
        );
      }
      if (TextNormalizer.hasDisallowedControlChars(
        k.displayValue,
        allowLineBreaks: false,
      )) {
        errors.add(field, 'invalid_chars', 'Keyword has control characters.');
      }
    }
  }

  /// Pure cross-input checks that need no database: no classification may be
  /// duplicated, and the primary must not also appear as an additional.
  void _validateClassificationShape(
    NormalizedDraft draft,
    ValidationErrorBuilder errors,
  ) {
    final List<DocumentClassificationInput> all = [
      if (draft.primaryClassification != null) draft.primaryClassification!,
      ...draft.additionalClassifications,
    ];
    final Set<String> seen = {};
    for (final c in all) {
      final String sig = '${c.mainCategoryId}:${c.subCategoryId ?? '_'}';
      if (!seen.add(sig)) {
        errors.add(
          'classifications',
          'duplicate_classification',
          'A classification (main ${c.mainCategoryId}, sub '
              '${c.subCategoryId}) appears more than once.',
        );
      }
    }
  }

  void _name(ValidationErrorBuilder errors, String field, String? value) {
    if (value == null) return;
    if (value.length > FieldLimits.name) {
      errors.add(
        field,
        'too_long',
        'Must be at most ${FieldLimits.name} characters.',
      );
    }
    if (TextNormalizer.hasDisallowedControlChars(
      value,
      allowLineBreaks: false,
    )) {
      errors.add(field, 'invalid_chars', 'Contains control characters.');
    }
  }

  void _notes(ValidationErrorBuilder errors, String field, String? value) {
    if (value == null) return;
    if (value.length > FieldLimits.notes) {
      errors.add(
        field,
        'too_long',
        'Must be at most ${FieldLimits.notes} characters.',
      );
    }
    if (TextNormalizer.hasDisallowedControlChars(
      value,
      allowLineBreaks: true,
    )) {
      errors.add(field, 'invalid_chars', 'Contains control characters.');
    }
  }

  void _constrained(
    ValidationErrorBuilder errors,
    String field,
    String? value,
    Set<String> allowed,
  ) {
    if (value == null) return;
    if (!allowed.contains(value)) {
      errors.add(field, 'invalid_value', 'Value "$value" is not allowed.');
    }
  }

  void _isoDate(ValidationErrorBuilder errors, String field, String? value) {
    if (value == null) return;
    if (!TextNormalizer.isIsoDate(value)) {
      errors.add(field, 'invalid_date', 'Must be an ISO date (YYYY-MM-DD).');
    }
  }
}
