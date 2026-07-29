// lib/features/documents/domain/validation/metadata_normalizer.dart

import '../../../../core/validation/text_normalizer.dart';
import '../entities/document_common_metadata.dart';
import '../entities/document_type_details.dart';
import '../entities/draft_save_input.dart';
import '../entities/keyword_input.dart';
import '../entities/normalized_draft.dart';
import 'keyword_normalizer.dart';

/// Pure normalization of a [DraftSaveInput] into a [NormalizedDraft]:
/// trims text, converts empty optionals to null, and reduces keywords to unique
/// normalized entries (preserving the first display value seen).
abstract final class MetadataNormalizer {
  static NormalizedDraft normalize(DraftSaveInput input) {
    return NormalizedDraft(
      documentId: input.documentId,
      common: _common(input.common),
      details: _details(input.details),
      primaryClassification: input.primaryClassification,
      additionalClassifications: input.additionalClassifications,
      keywords: _keywords(input.keywords),
    );
  }

  static DocumentCommonMetadata _common(DocumentCommonMetadata c) {
    String? t(String? v) => TextNormalizer.normalizeOptional(v);
    return DocumentCommonMetadata(
      documentTypeId: c.documentTypeId,
      title: t(c.title),
      languageKey: t(c.languageKey),
      languageOther: t(c.languageOther),
      countryKey: t(c.countryKey),
      publicationYear: c.publicationYear,
      summary: t(c.summary),
      sourceDescription: t(c.sourceDescription),
      trustLevelKey: t(c.trustLevelKey),
      usageRightsKey: t(c.usageRightsKey),
      metadataQualityKey: t(c.metadataQualityKey),
      reviewNotes: t(c.reviewNotes),
    );
  }

  static DocumentTypeDetails? _details(DocumentTypeDetails? d) {
    String? t(String? v) => TextNormalizer.normalizeOptional(v);
    return switch (d) {
      null => null,
      BookDetailsData() => BookDetailsData(
        author: t(d.author),
        publisher: t(d.publisher),
        publicationPlace: t(d.publicationPlace),
      ),
      ThesisDetailsData() => ThesisDetailsData(
        researcherName: t(d.researcherName),
        degreeTypeKey: t(d.degreeTypeKey),
        universityName: t(d.universityName),
        supervisorName: t(d.supervisorName),
      ),
      ResearchDetailsData() => ResearchDetailsData(
        researcherName: t(d.researcherName),
        journalName: t(d.journalName),
        publishingEntity: t(d.publishingEntity),
        volume: t(d.volume),
        issue: t(d.issue),
      ),
      LegislationDetailsData() => LegislationDetailsData(
        legislationTypeKey: t(d.legislationTypeKey),
        legislationTypeOther: t(d.legislationTypeOther),
        effectiveStatusKey: t(d.effectiveStatusKey),
        issueNumber: t(d.issueNumber),
        publicationDate: t(d.publicationDate),
        legislationNumber: t(d.legislationNumber),
        legislationYear: d.legislationYear,
        effectiveDate: t(d.effectiveDate),
        repealDate: t(d.repealDate),
      ),
      CourtCaseDetailsData() => CourtCaseDetailsData(
        courtName: t(d.courtName),
        caseNumber: t(d.caseNumber),
        judgmentDate: t(d.judgmentDate),
        judgmentResult: t(d.judgmentResult),
        legalPrinciple: t(d.legalPrinciple),
      ),
      ReportDetailsData() => ReportDetailsData(
        publishingEntity: t(d.publishingEntity),
      ),
    };
  }

  /// Normalizes keywords and removes duplicates by normalized value, keeping the
  /// first display value/language seen. Blank entries are preserved (with an
  /// empty normalized value) so field validation can reject them explicitly.
  static List<NormalizedKeyword> _keywords(List<KeywordInput> keywords) {
    final List<NormalizedKeyword> result = [];
    final Set<String> seen = {};
    for (final KeywordInput k in keywords) {
      final String display = KeywordNormalizer.displayOf(k.displayValue);
      final String normalized = KeywordNormalizer.normalizedOf(k.displayValue);
      if (normalized.isNotEmpty && !seen.add(normalized)) continue;
      result.add(
        NormalizedKeyword(
          displayValue: display,
          normalizedValue: normalized,
          languageKey: TextNormalizer.normalizeOptional(k.languageKey),
        ),
      );
    }
    return result;
  }
}
