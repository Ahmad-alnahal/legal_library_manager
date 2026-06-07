// lib/features/documents/data/repositories/drift_document_metadata_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/document_aggregate.dart';
import '../../domain/entities/document_classification_input.dart';
import '../../domain/entities/document_common_metadata.dart';
import '../../domain/entities/document_conversion_ref.dart';
import '../../domain/entities/document_file_ref.dart';
import '../../domain/entities/document_type_details.dart';
import '../../domain/entities/keyword_input.dart';
import '../../domain/entities/normalized_draft.dart';
import '../../domain/repositories/document_metadata_repository.dart';

/// Drift-backed implementation of [DocumentMetadataRepository].
///
/// All Drift row/companion types are confined to this class; its public surface
/// only exposes domain models. Multi-step writes run inside a single
/// transaction so a failure rolls back every metadata change.
class DriftDocumentMetadataRepository implements DocumentMetadataRepository {
  DriftDocumentMetadataRepository(this._db);

  final AppDatabase _db;

  @override
  Future<DocumentAggregate?> loadAggregate(int documentId) async {
    final Document? doc = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).getSingleOrNull();
    if (doc == null) return null;

    String? typeKey;
    final int? typeId = doc.documentTypeId;
    if (typeId != null) {
      final DocumentType? type = await (_db.select(
        _db.documentTypes,
      )..where((t) => t.id.equals(typeId))).getSingleOrNull();
      typeKey = type?.key;
    }

    final DocumentTypeDetails? details = await _loadDetails(
      documentId,
      typeKey,
    );

    final List<DocumentClassification> classifications = await (_db.select(
      _db.documentClassifications,
    )..where((c) => c.documentId.equals(documentId))).get();
    DocumentClassificationInput? primary;
    final List<DocumentClassificationInput> additional = [];
    for (final DocumentClassification c in classifications) {
      final input = DocumentClassificationInput(
        mainCategoryId: c.mainCategoryId,
        subCategoryId: c.subCategoryId,
      );
      if (c.classificationRoleKey == 'primary') {
        primary = input;
      } else {
        additional.add(input);
      }
    }

    final List<DocumentKeyword> links = await (_db.select(
      _db.documentKeywords,
    )..where((dk) => dk.documentId.equals(documentId))).get();
    final List<KeywordInput> keywords = [];
    for (final DocumentKeyword link in links) {
      final Keyword? kw = await (_db.select(
        _db.keywords,
      )..where((k) => k.id.equals(link.keywordId))).getSingleOrNull();
      if (kw != null) {
        keywords.add(
          KeywordInput(
            displayValue: kw.displayValue,
            languageKey: kw.languageKey,
          ),
        );
      }
    }

    final List<DocumentFile> files = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.documentId.equals(documentId))).get();
    final List<DocumentFileRef> fileRefs = files
        .map(
          (f) => DocumentFileRef(
            id: f.id,
            fileRoleKey: f.fileRoleKey,
            fileHealthKey: f.fileHealthKey,
          ),
        )
        .toList();

    final List<FileConversion> convs = await (_db.select(
      _db.fileConversions,
    )..where((c) => c.documentId.equals(documentId))).get();
    final List<DocumentConversionRef> conversionRefs = convs
        .map(
          (c) => DocumentConversionRef(
            statusKey: c.statusKey,
            outputFileId: c.outputFileId,
            qualityApproved: c.qualityApproved,
          ),
        )
        .toList();

    return DocumentAggregate(
      documentId: doc.id,
      workflowStatusKey: doc.workflowStatusKey,
      common: DocumentCommonMetadata(
        documentTypeId: doc.documentTypeId,
        title: doc.title,
        languageKey: doc.languageKey,
        countryKey: doc.countryKey,
        publicationYear: doc.publicationYear,
        summary: doc.summary,
        sourceDescription: doc.sourceDescription,
        trustLevelKey: doc.trustLevelKey,
        usageRightsKey: doc.usageRightsKey,
        metadataQualityKey: doc.metadataQualityKey,
        reviewNotes: doc.reviewNotes,
      ),
      details: details,
      primaryClassification: primary,
      additionalClassifications: additional,
      keywords: keywords,
      files: fileRefs,
      conversions: conversionRefs,
      documentCode: doc.documentCode,
      classifiedAt: doc.classifiedAt,
    );
  }

  @override
  Future<void> saveDraft(
    NormalizedDraft draft, {
    required DateTime now,
    required String workflowStatusKey,
    required bool clearClassifiedAt,
  }) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      await _ensureExists(draft.documentId);
      final DocumentCommonMetadata c = draft.common;
      final primary = draft.primaryClassification;

      await (_db.update(
        _db.documents,
      )..where((d) => d.id.equals(draft.documentId))).write(
        DocumentsCompanion(
          documentTypeId: Value(c.documentTypeId),
          title: Value(c.title),
          primaryMainCategoryId: Value(primary?.mainCategoryId),
          primarySubCategoryId: Value(primary?.subCategoryId),
          languageKey: Value(c.languageKey),
          countryKey: Value(c.countryKey),
          publicationYear: Value(c.publicationYear),
          summary: Value(c.summary),
          sourceDescription: Value(c.sourceDescription),
          // NOT-NULL columns with defaults: only overwrite when supplied.
          trustLevelKey: c.trustLevelKey == null
              ? const Value.absent()
              : Value(c.trustLevelKey!),
          usageRightsKey: c.usageRightsKey == null
              ? const Value.absent()
              : Value(c.usageRightsKey!),
          metadataQualityKey: c.metadataQualityKey == null
              ? const Value.absent()
              : Value(c.metadataQualityKey!),
          reviewNotes: Value(c.reviewNotes),
          workflowStatusKey: Value(workflowStatusKey),
          // Preserve existing classified_at unless explicitly clearing it.
          classifiedAt: clearClassifiedAt
              ? const Value(null)
              : const Value.absent(),
          updatedAt: Value(nowIso),
        ),
      );

      await _replaceDetails(draft.documentId, draft.details);
      await _replaceClassifications(
        draft.documentId,
        primary,
        draft.additionalClassifications,
        nowIso,
      );
      await _replaceKeywords(draft.documentId, draft.keywords, nowIso);
    });
  }

  @override
  Future<void> markClassified(int documentId, {required DateTime now}) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      await _ensureExists(documentId);
      final DocumentClassification? primary =
          await (_db.select(_db.documentClassifications)..where(
                (c) =>
                    c.documentId.equals(documentId) &
                    c.classificationRoleKey.equals('primary'),
              ))
              .getSingleOrNull();

      await (_db.update(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).write(
        DocumentsCompanion(
          primaryMainCategoryId: Value(primary?.mainCategoryId),
          primarySubCategoryId: Value(primary?.subCategoryId),
          workflowStatusKey: const Value('classified'),
          classifiedAt: Value(nowIso),
          updatedAt: Value(nowIso),
        ),
      );
    });
  }

  // --- internal helpers (all Drift types stay here) ---

  Future<void> _ensureExists(int documentId) async {
    final Document? doc = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).getSingleOrNull();
    if (doc == null) {
      throw StateError('Document $documentId does not exist.');
    }
  }

  Future<DocumentTypeDetails?> _loadDetails(
    int documentId,
    String? typeKey,
  ) async {
    switch (typeKey) {
      case 'book':
        final r = await (_db.select(
          _db.bookDetails,
        )..where((b) => b.documentId.equals(documentId))).getSingleOrNull();
        return r == null
            ? null
            : BookDetailsData(
                author: r.author,
                publisher: r.publisher,
                publicationPlace: r.publicationPlace,
              );
      case 'thesis':
        final r = await (_db.select(
          _db.thesisDetails,
        )..where((b) => b.documentId.equals(documentId))).getSingleOrNull();
        return r == null
            ? null
            : ThesisDetailsData(
                researcherName: r.researcherName,
                degreeTypeKey: r.degreeTypeKey,
                universityName: r.universityName,
                supervisorName: r.supervisorName,
              );
      case 'research_paper':
        final r = await (_db.select(
          _db.researchDetails,
        )..where((b) => b.documentId.equals(documentId))).getSingleOrNull();
        return r == null
            ? null
            : ResearchDetailsData(
                researcherName: r.researcherName,
                journalName: r.journalName,
                publishingEntity: r.publishingEntity,
                volume: r.volume,
                issue: r.issue,
              );
      case 'legislation':
        final r = await (_db.select(
          _db.legislationDetails,
        )..where((b) => b.documentId.equals(documentId))).getSingleOrNull();
        return r == null
            ? null
            : LegislationDetailsData(
                legislationTypeKey: r.legislationTypeKey,
                effectiveStatusKey: r.effectiveStatusKey,
                issueNumber: r.issueNumber,
                publicationDate: r.publicationDate,
              );
      case 'court_precedent':
        final r = await (_db.select(
          _db.courtCaseDetails,
        )..where((b) => b.documentId.equals(documentId))).getSingleOrNull();
        return r == null
            ? null
            : CourtCaseDetailsData(
                courtName: r.courtName,
                caseNumber: r.caseNumber,
                judgmentDate: r.judgmentDate,
                judgmentResult: r.judgmentResult,
                legalPrinciple: r.legalPrinciple,
              );
      case 'institutional_report':
        final r = await (_db.select(
          _db.reportDetails,
        )..where((b) => b.documentId.equals(documentId))).getSingleOrNull();
        return r == null
            ? null
            : ReportDetailsData(publishingEntity: r.publishingEntity);
      default:
        return null;
    }
  }

  /// Removes every detail row for the document, then inserts the one matching
  /// the current type (if any) — so changing type drops obsolete detail rows.
  Future<void> _replaceDetails(
    int documentId,
    DocumentTypeDetails? details,
  ) async {
    await (_db.delete(
      _db.bookDetails,
    )..where((b) => b.documentId.equals(documentId))).go();
    await (_db.delete(
      _db.thesisDetails,
    )..where((b) => b.documentId.equals(documentId))).go();
    await (_db.delete(
      _db.researchDetails,
    )..where((b) => b.documentId.equals(documentId))).go();
    await (_db.delete(
      _db.legislationDetails,
    )..where((b) => b.documentId.equals(documentId))).go();
    await (_db.delete(
      _db.courtCaseDetails,
    )..where((b) => b.documentId.equals(documentId))).go();
    await (_db.delete(
      _db.reportDetails,
    )..where((b) => b.documentId.equals(documentId))).go();

    switch (details) {
      case null:
        return;
      case BookDetailsData():
        await _db
            .into(_db.bookDetails)
            .insert(
              BookDetailsCompanion.insert(
                documentId: documentId,
                author: Value(details.author),
                publisher: Value(details.publisher),
                publicationPlace: Value(details.publicationPlace),
              ),
            );
      case ThesisDetailsData():
        await _db
            .into(_db.thesisDetails)
            .insert(
              ThesisDetailsCompanion.insert(
                documentId: documentId,
                researcherName: Value(details.researcherName),
                degreeTypeKey: Value(details.degreeTypeKey),
                universityName: Value(details.universityName),
                supervisorName: Value(details.supervisorName),
              ),
            );
      case ResearchDetailsData():
        await _db
            .into(_db.researchDetails)
            .insert(
              ResearchDetailsCompanion.insert(
                documentId: documentId,
                researcherName: Value(details.researcherName),
                journalName: Value(details.journalName),
                publishingEntity: Value(details.publishingEntity),
                volume: Value(details.volume),
                issue: Value(details.issue),
              ),
            );
      case LegislationDetailsData():
        await _db
            .into(_db.legislationDetails)
            .insert(
              LegislationDetailsCompanion.insert(
                documentId: documentId,
                legislationTypeKey: Value(details.legislationTypeKey),
                effectiveStatusKey: Value(details.effectiveStatusKey),
                issueNumber: Value(details.issueNumber),
                publicationDate: Value(details.publicationDate),
              ),
            );
      case CourtCaseDetailsData():
        await _db
            .into(_db.courtCaseDetails)
            .insert(
              CourtCaseDetailsCompanion.insert(
                documentId: documentId,
                courtName: Value(details.courtName),
                caseNumber: Value(details.caseNumber),
                judgmentDate: Value(details.judgmentDate),
                judgmentResult: Value(details.judgmentResult),
                legalPrinciple: Value(details.legalPrinciple),
              ),
            );
      case ReportDetailsData():
        await _db
            .into(_db.reportDetails)
            .insert(
              ReportDetailsCompanion.insert(
                documentId: documentId,
                publishingEntity: Value(details.publishingEntity),
              ),
            );
    }
  }

  Future<void> _replaceClassifications(
    int documentId,
    DocumentClassificationInput? primary,
    List<DocumentClassificationInput> additional,
    String nowIso,
  ) async {
    await (_db.delete(
      _db.documentClassifications,
    )..where((c) => c.documentId.equals(documentId))).go();

    if (primary != null) {
      await _db
          .into(_db.documentClassifications)
          .insert(
            DocumentClassificationsCompanion.insert(
              documentId: documentId,
              mainCategoryId: primary.mainCategoryId,
              classificationRoleKey: 'primary',
              createdAt: nowIso,
              subCategoryId: Value(primary.subCategoryId),
            ),
          );
    }
    for (final DocumentClassificationInput a in additional) {
      await _db
          .into(_db.documentClassifications)
          .insert(
            DocumentClassificationsCompanion.insert(
              documentId: documentId,
              mainCategoryId: a.mainCategoryId,
              classificationRoleKey: 'additional',
              createdAt: nowIso,
              subCategoryId: Value(a.subCategoryId),
            ),
          );
    }
  }

  /// Replaces the document's keyword links, reusing keyword rows by normalized
  /// value rather than duplicating them.
  Future<void> _replaceKeywords(
    int documentId,
    List<NormalizedKeyword> keywords,
    String nowIso,
  ) async {
    await (_db.delete(
      _db.documentKeywords,
    )..where((dk) => dk.documentId.equals(documentId))).go();

    for (final NormalizedKeyword k in keywords) {
      final Keyword? existing =
          await (_db.select(_db.keywords)
                ..where((kw) => kw.normalizedValue.equals(k.normalizedValue)))
              .getSingleOrNull();
      final int keywordId =
          existing?.id ??
          await _db
              .into(_db.keywords)
              .insert(
                KeywordsCompanion.insert(
                  normalizedValue: k.normalizedValue,
                  displayValue: k.displayValue,
                  createdAt: nowIso,
                  languageKey: Value(k.languageKey),
                ),
              );
      await _db
          .into(_db.documentKeywords)
          .insert(
            DocumentKeywordsCompanion.insert(
              documentId: documentId,
              keywordId: keywordId,
              createdAt: nowIso,
            ),
          );
    }
  }
}
