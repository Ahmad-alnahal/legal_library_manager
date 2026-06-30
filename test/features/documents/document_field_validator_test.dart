import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_classification_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_common_metadata.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_type_details.dart';
import 'package:legal_library_manager/features/documents/domain/entities/draft_save_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/keyword_input.dart';
import 'package:legal_library_manager/features/documents/domain/validation/document_field_validator.dart';
import 'package:legal_library_manager/features/documents/domain/validation/metadata_normalizer.dart';

import 'support/document_test_support.dart';

void main() {
  // Year-sensitive tests use a fixed clock at 2026.
  final validator = DocumentFieldValidator(
    FixedClock(DateTime.utc(2026, 6, 7)),
  );

  DraftSaveInput draft({
    DocumentCommonMetadata? common,
    DocumentTypeDetails? details,
    DocumentClassificationInput? primary,
    List<DocumentClassificationInput> additional = const [],
    List<KeywordInput> keywords = const [],
  }) => DraftSaveInput(
    documentId: 1,
    common: common ?? const DocumentCommonMetadata(),
    details: details,
    primaryClassification: primary,
    additionalClassifications: additional,
    keywords: keywords,
  );

  group('DocumentFieldValidator', () {
    test('empty draft is valid (drafts may be incomplete)', () {
      final r = validator.validate(MetadataNormalizer.normalize(draft()));
      expect(r.isValid, isTrue);
    });

    test('rejects over-length title', () {
      final r = validator.validate(
        MetadataNormalizer.normalize(
          draft(common: DocumentCommonMetadata(title: 'x' * 501)),
        ),
      );
      expect(r.hasError('title'), isTrue);
      expect(r.hasCode('too_long'), isTrue);
    });

    test('rejects control characters in single-line fields', () {
      final r = validator.validate(
        MetadataNormalizer.normalize(
          draft(common: const DocumentCommonMetadata(title: 'a\tb')),
        ),
      );
      expect(r.hasError('title'), isTrue);
      expect(r.hasCode('invalid_chars'), isTrue);
    });

    test('allows line breaks in summary/notes', () {
      final r = validator.validate(
        MetadataNormalizer.normalize(
          draft(common: const DocumentCommonMetadata(summary: 'line1\nline2')),
        ),
      );
      expect(r.isValid, isTrue);
    });

    test('enforces publication year range using injected clock', () {
      expect(
        validator
            .validate(
              MetadataNormalizer.normalize(
                draft(
                  common: const DocumentCommonMetadata(publicationYear: 999),
                ),
              ),
            )
            .hasError('publicationYear'),
        isTrue,
      );
      // currentYear + 1 = 2027 is the max.
      expect(
        validator
            .validate(
              MetadataNormalizer.normalize(
                draft(
                  common: const DocumentCommonMetadata(publicationYear: 2028),
                ),
              ),
            )
            .hasError('publicationYear'),
        isTrue,
      );
      expect(
        validator
            .validate(
              MetadataNormalizer.normalize(
                draft(
                  common: const DocumentCommonMetadata(publicationYear: 2027),
                ),
              ),
            )
            .isValid,
        isTrue,
      );
    });

    test('rejects invalid constrained detail keys', () {
      final r = validator.validate(
        MetadataNormalizer.normalize(
          draft(details: const ThesisDetailsData(degreeTypeKey: 'phd')),
        ),
      );
      expect(r.hasError('thesis.degreeTypeKey'), isTrue);
      expect(r.hasCode('invalid_value'), isTrue);
    });

    test('rejects malformed legislation publication date', () {
      final r = validator.validate(
        MetadataNormalizer.normalize(
          draft(
            details: const LegislationDetailsData(
              publicationDate: '2026-13-40',
            ),
          ),
        ),
      );
      expect(r.hasError('legislation.publicationDate'), isTrue);
    });

    test('requires custom legislation type text when type is other', () {
      final missing = validator.validate(
        MetadataNormalizer.normalize(
          draft(
            details: const LegislationDetailsData(legislationTypeKey: 'other'),
          ),
        ),
      );
      expect(missing.hasError('legislation.legislationTypeOther'), isTrue);
      expect(missing.hasCode('required'), isTrue);

      final filled = validator.validate(
        MetadataNormalizer.normalize(
          draft(
            details: const LegislationDetailsData(
              legislationTypeKey: 'other',
              legislationTypeOther: 'تعليمات خاصة',
            ),
          ),
        ),
      );
      expect(filled.isValid, isTrue);
    });

    test('accepts v6 effective statuses and validates legislation dates', () {
      final valid = validator.validate(
        MetadataNormalizer.normalize(
          draft(
            details: const LegislationDetailsData(
              effectiveStatusKey: 'amended',
              legislationYear: 2024,
              effectiveDate: '2024-01-01',
              repealDate: '2025-01-01',
            ),
          ),
        ),
      );
      expect(valid.isValid, isTrue);

      final invalid = validator.validate(
        MetadataNormalizer.normalize(
          draft(
            details: const LegislationDetailsData(
              effectiveStatusKey: 'suspended',
              legislationYear: 3000,
              effectiveDate: '2024-99-99',
            ),
          ),
        ),
      );
      expect(invalid.hasError('legislation.effectiveStatusKey'), isTrue);
      expect(invalid.hasError('legislation.legislationYear'), isTrue);
      expect(invalid.hasError('legislation.effectiveDate'), isTrue);
    });

    test('rejects blank and overlong keywords', () {
      final blank = validator.validate(
        MetadataNormalizer.normalize(
          draft(keywords: const [KeywordInput(displayValue: '   ')]),
        ),
      );
      expect(blank.hasCode('blank'), isTrue);

      final long = validator.validate(
        MetadataNormalizer.normalize(
          draft(keywords: [KeywordInput(displayValue: 'k' * 151)]),
        ),
      );
      expect(long.hasCode('too_long'), isTrue);
    });

    test('flags duplicate classifications including primary-in-additional', () {
      final r = validator.validate(
        MetadataNormalizer.normalize(
          draft(
            primary: const DocumentClassificationInput(
              mainCategoryId: 1,
              subCategoryId: 2,
            ),
            additional: const [
              DocumentClassificationInput(mainCategoryId: 1, subCategoryId: 2),
            ],
          ),
        ),
      );
      expect(r.hasCode('duplicate_classification'), isTrue);
    });
  });
}
