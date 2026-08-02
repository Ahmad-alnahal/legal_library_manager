// lib/features/documents/data/repositories/drift_document_metadata_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/database/app_database.dart';
import '../../../export/domain/entities/export_category_entry.dart';
import '../../../export/domain/entities/export_document_metadata.dart';
import '../../../export/domain/entities/export_eligibility_input.dart';
import '../../../export/domain/entities/export_eligibility_result.dart';
import '../../../export/domain/entities/export_keywords_result.dart';
import '../../../export/domain/entities/export_legislation_details.dart';
import '../../../export/domain/entities/export_legislation_relation.dart';
import '../../../export/domain/entities/exportable_document_ref.dart';
import '../../../export/domain/export_eligibility.dart' as export_eligibility;
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

    final List<DocumentFile> allFiles = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.documentId.equals(documentId))).get();
    // Only source_original files are subject to duplicate-hide filtering.
    // managed_copy / converted_pdf files must always appear in the aggregate
    // so that copy-health checks (hasMissingManagedCopy etc.) remain correct.
    final List<int> sourceFileIds = allFiles
        .where((f) => f.fileRoleKey == FileRoleKey.sourceOriginal)
        .map((f) => f.id)
        .toList(growable: false);
    final Set<int> hiddenSourceFileIds = await _hiddenDuplicateFileIds(
      sourceFileIds,
    );
    final List<DocumentFile> files = allFiles
        .where(
          (f) =>
              f.fileRoleKey != FileRoleKey.sourceOriginal ||
              !hiddenSourceFileIds.contains(f.id),
        )
        .toList(growable: false);
    final List<DocumentFileRef> fileRefs = files
        .map(
          (f) => DocumentFileRef(
            id: f.id,
            fileRoleKey: f.fileRoleKey,
            fileHealthKey: f.fileHealthKey,
          ),
        )
        .toList();

    // Preferred original source filename: prefer the explicitly-preferred row,
    // then any file marked as preferred_file_id in a duplicate group (defensive
    // fallback for data predating the is_preferred sync), then the lowest id,
    // among `source_original` files. Read-only projection.
    final List<DocumentFile> sourceFiles = files
        .where((f) => f.fileRoleKey == FileRoleKey.sourceOriginal)
        .toList();
    final Set<int> groupPreferredIds = await _groupPreferredFileIds(
      sourceFiles.map((f) => f.id).toList(),
    );
    sourceFiles.sort((a, b) {
      if (a.isPreferred != b.isPreferred) return a.isPreferred ? -1 : 1;
      final aPref = groupPreferredIds.contains(a.id);
      final bPref = groupPreferredIds.contains(b.id);
      if (aPref != bPref) return aPref ? -1 : 1;
      return a.id.compareTo(b.id);
    });
    final String? preferredSourceFileName = sourceFiles.isEmpty
        ? null
        : sourceFiles.first.fileName;

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
        languageOther: doc.languageOther,
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
      preferredSourceFileName: preferredSourceFileName,
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
          languageOther: Value(c.languageOther),
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
      await _db.updateDocumentFts(draft.documentId);
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
          workflowStatusKey: const Value(WorkflowStatusKey.classified),
          classifiedAt: Value(nowIso),
          updatedAt: Value(nowIso),
        ),
      );
    });
  }

  @override
  Future<void> returnToInProgress(int documentId, {required DateTime now}) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      await _ensureExists(documentId);
      await (_db.update(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).write(
        DocumentsCompanion(
          workflowStatusKey: const Value(WorkflowStatusKey.inProgress),
          classifiedAt: const Value(null),
          updatedAt: Value(nowIso),
        ),
      );
      await _db.updateDocumentFts(documentId);
    });
  }

  @override
  Future<ExportEligibilityResult> checkExportEligibility(int documentId) async {
    final Document? doc = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).getSingleOrNull();
    if (doc == null) {
      throw StateError('Document $documentId does not exist.');
    }

    final bool hasHealthyManagedCopy =
        await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(documentId) &
                  f.fileRoleKey.equals(FileRoleKey.managedCopy) &
                  f.fileHealthKey.equals(FileHealthKey.healthy),
            ))
            .getSingleOrNull() !=
        null;

    bool? mainCategoryActive;
    final int? mainCategoryId = doc.primaryMainCategoryId;
    if (mainCategoryId != null) {
      final MainCategory? mainCategory = await (_db.select(
        _db.mainCategories,
      )..where((m) => m.id.equals(mainCategoryId))).getSingleOrNull();
      mainCategoryActive = mainCategory?.isActive;
    }

    bool? subCategoryActive;
    final int? subCategoryId = doc.primarySubCategoryId;
    if (subCategoryId != null) {
      final SubCategory? subCategory = await (_db.select(
        _db.subCategories,
      )..where((s) => s.id.equals(subCategoryId))).getSingleOrNull();
      subCategoryActive = subCategory?.isActive;
    }

    return export_eligibility.checkExportEligibility(
      ExportEligibilityInput(
        workflowStatusKey: doc.workflowStatusKey,
        hasHealthyManagedCopy: hasHealthyManagedCopy,
        primaryMainCategoryId: mainCategoryId,
        primaryMainCategoryActive: mainCategoryActive,
        primarySubCategoryId: subCategoryId,
        primarySubCategoryActive: subCategoryActive,
        metadataQualityKey: doc.metadataQualityKey,
        usageRightsKey: doc.usageRightsKey,
      ),
    );
  }

  @override
  Future<void> markReadyForExport(int documentId, {required DateTime now}) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      final int updatedRows =
          await (_db.update(_db.documents)..where(
                (d) =>
                    d.id.equals(documentId) &
                    d.workflowStatusKey.equals(
                      WorkflowStatusKey.copiedToLibrary,
                    ),
              ))
              .write(
                DocumentsCompanion(
                  workflowStatusKey: const Value(
                    WorkflowStatusKey.readyForExport,
                  ),
                  readyForExportAt: Value(nowIso),
                  updatedAt: Value(nowIso),
                ),
              );
      if (updatedRows != 1) {
        throw StateError(
          'Document $documentId is not currently copied_to_library.',
        );
      }
    });
  }

  @override
  Future<List<ExportableDocumentRef>> listReadyForExport() async {
    final healthyCopies = _db.selectOnly(_db.documentFiles)
      ..addColumns([_db.documentFiles.documentId])
      ..where(
        _db.documentFiles.fileRoleKey.equals(FileRoleKey.managedCopy) &
            _db.documentFiles.fileHealthKey.equals(FileHealthKey.healthy),
      );

    final List<Document> rows =
        await (_db.select(_db.documents)
              ..where(
                (d) =>
                    d.workflowStatusKey.equals(
                      WorkflowStatusKey.readyForExport,
                    ) &
                    d.id.isInQuery(healthyCopies),
              )
              ..orderBy([(d) => OrderingTerm.asc(d.readyForExportAt)]))
            .get();
    return rows
        .map(
          (d) => ExportableDocumentRef(
            id: d.id,
            documentCode: d.documentCode!,
            readyForExportAt: DateTime.parse(d.readyForExportAt!),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ExportDocumentMetadata>> loadExportMetadata(
    List<int> documentIds,
  ) async {
    if (documentIds.isEmpty) return const [];

    final String placeholders = List.filled(documentIds.length, '?').join(',');
    final List<QueryRow> rows = await _db
        .customSelect(
          '''
SELECT
  d.id AS doc_id,
  d.document_code AS document_code,
  d.title AS title_ar,
  dt.key AS document_type_key,
  dt.name_ar AS document_type_name_ar,
  dt.name_en AS document_type_name_en,
  mc.key AS main_category_key,
  mc.name_ar AS main_category_name_ar,
  mc.name_en AS main_category_name_en,
  sc.key AS sub_category_key,
  sc.name_ar AS sub_category_name_ar,
  sc.name_en AS sub_category_name_en,
  co.key AS country_code,
  co.name_ar AS country_name_ar,
  co.name_en AS country_name_en,
  lang.key AS language_key,
  lang.name_ar AS language_name_ar,
  lang.name_en AS language_name_en,
  d.language_other AS language_other,
  d.trust_level_key AS trust_level_key,
  d.usage_rights_key AS usage_rights_key,
  d.metadata_quality_key AS metadata_quality_key,
  d.summary AS summary_ar,
  d.ready_for_export_at AS ready_for_export_at,
  ld.legislation_number AS legislation_number,
  ld.legislation_year AS legislation_year,
  ld.effective_date AS effective_date,
  ld.repeal_date AS repeal_date,
  ld.effective_status_key AS effective_status_key,
  ld.legislation_type_key AS legislation_type_key,
  ld.legislation_type_other AS legislation_type_other
FROM documents d
LEFT JOIN document_types dt ON dt.id = d.document_type_id
LEFT JOIN main_categories mc ON mc.id = d.primary_main_category_id
LEFT JOIN sub_categories sc ON sc.id = d.primary_sub_category_id
LEFT JOIN countries co ON co.key = d.country_key
LEFT JOIN languages lang ON lang.key = d.language_key
LEFT JOIN legislation_details ld ON ld.document_id = d.id
WHERE d.id IN ($placeholders)
''',
          variables: [for (final int id in documentIds) Variable(id)],
          readsFrom: {
            _db.documents,
            _db.documentTypes,
            _db.mainCategories,
            _db.subCategories,
            _db.countries,
            _db.languages,
            _db.legislationDetails,
          },
        )
        .get();

    final Map<int, QueryRow> rowById = {
      for (final QueryRow row in rows) row.read<int>('doc_id'): row,
    };
    final List<int> legislationIds = rows
        .where((row) => row.read<String>('document_type_key') == 'legislation')
        .map((row) => row.read<int>('doc_id'))
        .toList(growable: false);

    final Map<int, List<String>> keywordsByDocId = await _loadKeywordTexts(
      rowById.keys.toList(growable: false),
    );
    final Map<int, List<ExportLegislationRelation>> relationsByDocId =
        await _loadLegislationRelations(legislationIds);

    final List<ExportDocumentMetadata> result = [];
    for (final int id in documentIds) {
      final QueryRow? row = rowById[id];
      if (row == null) continue;

      final String documentTypeKey = row.read<String>('document_type_key');
      final bool isLegislation = documentTypeKey == 'legislation';
      final String usageRightsKey = row.read<String>('usage_rights_key');
      final int? legislationYear = row.readNullable<int>('legislation_year');

      result.add(
        ExportDocumentMetadata(
          documentCode: row.read<String>('document_code'),
          titleAr: row.readNullable<String>('title_ar'),
          titleEn: null,
          documentTypeKey: documentTypeKey,
          documentTypeNameAr: row.read<String>('document_type_name_ar'),
          documentTypeNameEn: row.read<String>('document_type_name_en'),
          primaryMainCategoryKey: row.read<String>('main_category_key'),
          primaryMainCategoryNameAr: row.read<String>('main_category_name_ar'),
          primaryMainCategoryNameEn: row.read<String>('main_category_name_en'),
          primarySubcategoryKey: row.readNullable<String>('sub_category_key'),
          primarySubcategoryNameAr: row.readNullable<String>(
            'sub_category_name_ar',
          ),
          primarySubcategoryNameEn: row.readNullable<String>(
            'sub_category_name_en',
          ),
          countryCode: row.readNullable<String>('country_code'),
          countryNameAr: row.readNullable<String>('country_name_ar'),
          countryNameEn: row.readNullable<String>('country_name_en'),
          languageKey: row.readNullable<String>('language_key'),
          languageNameAr: row.readNullable<String>('language_name_ar'),
          languageNameEn: row.readNullable<String>('language_name_en'),
          languageOther: row.readNullable<String>('language_other'),
          trustLevelKey: row.read<String>('trust_level_key'),
          usageRightsKey: usageRightsKey,
          isUsageRightsFlagged:
              usageRightsKey == UsageRightsKey.personalUseOnly ||
              usageRightsKey == UsageRightsKey.permissionRequired,
          metadataQualityKey: row.read<String>('metadata_quality_key'),
          summaryAr: row.readNullable<String>('summary_ar'),
          readyForExportAt: DateTime.parse(
            row.read<String>('ready_for_export_at'),
          ),
          keywords: keywordsByDocId[id] ?? const [],
          legislationDetails: !isLegislation
              ? null
              : ExportLegislationDetails(
                  legislationNumber: row.readNullable<String>(
                    'legislation_number',
                  ),
                  legislationYear: legislationYear?.toString(),
                  effectiveDate: row.readNullable<String>('effective_date'),
                  repealDate: row.readNullable<String>('repeal_date'),
                  effectiveStatusKey: row.readNullable<String>(
                    'effective_status_key',
                  ),
                  legislationTypeKey: row.readNullable<String>(
                    'legislation_type_key',
                  ),
                  legislationTypeOther: row.readNullable<String>(
                    'legislation_type_other',
                  ),
                ),
          legislationRelations: !isLegislation
              ? const []
              : (relationsByDocId[id] ?? const []),
        ),
      );
    }
    return result;
  }

  @override
  Future<List<ExportCategoryEntry>> loadExportCategories() async {
    final List<QueryRow> rows = await _db
        .customSelect(
          '''
SELECT
  mc.key AS main_key,
  mc.name_ar AS main_name_ar,
  mc.name_en AS main_name_en,
  mc.sort_order AS main_sort,
  sc.key AS sub_key,
  sc.name_ar AS sub_name_ar,
  sc.name_en AS sub_name_en,
  sc.sort_order AS sub_sort
FROM main_categories mc
LEFT JOIN sub_categories sc
  ON sc.main_category_id = mc.id AND sc.is_active = 1
WHERE mc.is_active = 1
ORDER BY mc.sort_order ASC, sc.sort_order ASC
''',
          readsFrom: {_db.mainCategories, _db.subCategories},
        )
        .get();

    final Map<String, ExportCategoryEntry> byKey = {};
    final List<String> order = [];
    final Map<String, List<ExportSubcategoryEntry>> subsByMainKey = {};

    for (final QueryRow row in rows) {
      final String mainKey = row.read<String>('main_key');
      if (!byKey.containsKey(mainKey)) {
        order.add(mainKey);
        subsByMainKey[mainKey] = [];
        byKey[mainKey] = ExportCategoryEntry(
          mainCategoryKey: mainKey,
          mainCategoryNameAr: row.read<String>('main_name_ar'),
          mainCategoryNameEn: row.read<String>('main_name_en'),
          sortOrder: row.read<int>('main_sort'),
          subcategories: const [],
        );
      }
      final String? subKey = row.readNullable<String>('sub_key');
      if (subKey != null) {
        subsByMainKey[mainKey]!.add(
          ExportSubcategoryEntry(
            subcategoryKey: subKey,
            subcategoryNameAr: row.read<String>('sub_name_ar'),
            subcategoryNameEn: row.read<String>('sub_name_en'),
            sortOrder: row.read<int>('sub_sort'),
          ),
        );
      }
    }

    return order
        .map(
          (key) => ExportCategoryEntry(
            mainCategoryKey: byKey[key]!.mainCategoryKey,
            mainCategoryNameAr: byKey[key]!.mainCategoryNameAr,
            mainCategoryNameEn: byKey[key]!.mainCategoryNameEn,
            sortOrder: byKey[key]!.sortOrder,
            subcategories: subsByMainKey[key]!,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ExportKeywordsResult> loadExportKeywords(List<int> documentIds) async {
    if (documentIds.isEmpty) {
      return const ExportKeywordsResult(keywords: [], documentKeywords: []);
    }

    final String placeholders = List.filled(documentIds.length, '?').join(',');

    final List<QueryRow> keywordRows = await _db
        .customSelect(
          '''
SELECT DISTINCT k.display_value AS display_value
FROM document_keywords dk
JOIN keywords k ON k.id = dk.keyword_id
WHERE dk.document_id IN ($placeholders)
ORDER BY k.display_value ASC
''',
          variables: [for (final int id in documentIds) Variable(id)],
          readsFrom: {_db.documentKeywords, _db.keywords},
        )
        .get();

    final List<QueryRow> linkRows = await _db
        .customSelect(
          '''
SELECT d.document_code AS document_code, k.display_value AS display_value
FROM document_keywords dk
JOIN keywords k ON k.id = dk.keyword_id
JOIN documents d ON d.id = dk.document_id
WHERE dk.document_id IN ($placeholders)
ORDER BY d.document_code ASC, k.display_value ASC
''',
          variables: [for (final int id in documentIds) Variable(id)],
          readsFrom: {_db.documentKeywords, _db.keywords, _db.documents},
        )
        .get();

    return ExportKeywordsResult(
      keywords: keywordRows
          .map(
            (row) => ExportKeywordEntry(
              keywordText: row.read<String>('display_value'),
            ),
          )
          .toList(growable: false),
      documentKeywords: linkRows
          .map(
            (row) => ExportDocumentKeywordEntry(
              documentCode: row.read<String>('document_code'),
              keywordText: row.read<String>('display_value'),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<Map<int, List<String>>> _loadKeywordTexts(
    List<int> documentIds,
  ) async {
    if (documentIds.isEmpty) return const {};
    final String placeholders = List.filled(documentIds.length, '?').join(',');
    final List<QueryRow> rows = await _db
        .customSelect(
          '''
SELECT dk.document_id AS doc_id, k.display_value AS display_value
FROM document_keywords dk
JOIN keywords k ON k.id = dk.keyword_id
WHERE dk.document_id IN ($placeholders)
ORDER BY dk.document_id ASC, dk.created_at ASC, k.id ASC
''',
          variables: [for (final int id in documentIds) Variable(id)],
          readsFrom: {_db.documentKeywords, _db.keywords},
        )
        .get();

    final Map<int, List<String>> byDocId = {};
    for (final QueryRow row in rows) {
      final int docId = row.read<int>('doc_id');
      (byDocId[docId] ??= []).add(row.read<String>('display_value'));
    }
    return byDocId;
  }

  Future<Map<int, List<ExportLegislationRelation>>> _loadLegislationRelations(
    List<int> legislationDocumentIds,
  ) async {
    if (legislationDocumentIds.isEmpty) return const {};
    final String placeholders = List.filled(
      legislationDocumentIds.length,
      '?',
    ).join(',');
    final List<QueryRow> rows = await _db
        .customSelect(
          '''
SELECT
  lr.source_document_id AS source_doc_id,
  tgt.document_code AS target_document_code,
  lr.relation_type_key AS relation_type_key,
  lr.relation_scope_key AS scope_key,
  lr.effective_date AS effective_date,
  lr.notes AS notes
FROM legislation_relations lr
JOIN documents tgt ON tgt.id = lr.target_document_id
WHERE lr.source_document_id IN ($placeholders)
ORDER BY lr.created_at ASC
''',
          variables: [
            for (final int id in legislationDocumentIds) Variable(id),
          ],
          readsFrom: {_db.legislationRelations, _db.documents},
        )
        .get();

    final Map<int, List<ExportLegislationRelation>> byDocId = {};
    for (final QueryRow row in rows) {
      final int docId = row.read<int>('source_doc_id');
      (byDocId[docId] ??= []).add(
        ExportLegislationRelation(
          targetDocumentCode: row.read<String>('target_document_code'),
          relationTypeKey: row.read<String>('relation_type_key'),
          scope: row.readNullable<String>('scope_key'),
          effectiveDate: row.readNullable<String>('effective_date'),
          notes: row.readNullable<String>('notes'),
        ),
      );
    }
    return byDocId;
  }

  // --- internal helpers (all Drift types stay here) ---

  Future<Set<int>> _hiddenDuplicateFileIds(List<int> fileIds) async {
    if (fileIds.isEmpty) return const {};
    final rows =
        await (_db.select(_db.duplicateGroupMembers)..where(
              (m) => m.fileId.isIn(fileIds) & m.isHiddenFromSearch.equals(true),
            ))
            .get();
    return rows.map((r) => r.fileId).toSet();
  }

  /// Returns the subset of [fileIds] that are recorded as
  /// `preferred_file_id` in any duplicate group. Used as a fallback sort key
  /// when `document_files.is_preferred` has not yet been synced.
  Future<Set<int>> _groupPreferredFileIds(List<int> fileIds) async {
    if (fileIds.isEmpty) return const {};
    final rows =
        await (_db.selectOnly(_db.duplicateGroups)
              ..addColumns([_db.duplicateGroups.preferredFileId])
              ..where(_db.duplicateGroups.preferredFileId.isIn(fileIds)))
            .get();
    return rows
        .map((r) => r.read(_db.duplicateGroups.preferredFileId))
        .whereType<int>()
        .toSet();
  }

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
                legislationTypeOther: r.legislationTypeOther,
                effectiveStatusKey: r.effectiveStatusKey,
                issueNumber: r.issueNumber,
                publicationDate: r.publicationDate,
                legislationNumber: r.legislationNumber,
                legislationYear: r.legislationYear,
                effectiveDate: r.effectiveDate,
                repealDate: r.repealDate,
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
                legislationTypeOther: Value(details.legislationTypeOther),
                effectiveStatusKey: Value(details.effectiveStatusKey),
                issueNumber: Value(details.issueNumber),
                publicationDate: Value(details.publicationDate),
                legislationNumber: Value(details.legislationNumber),
                legislationYear: Value(details.legislationYear),
                effectiveDate: Value(details.effectiveDate),
                repealDate: Value(details.repealDate),
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
