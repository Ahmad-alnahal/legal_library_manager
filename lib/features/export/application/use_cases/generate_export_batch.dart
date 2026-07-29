// lib/features/export/application/use_cases/generate_export_batch.dart

import 'dart:convert';

import '../../../../core/time/clock.dart';
import '../../../documents/domain/repositories/document_metadata_repository.dart';
import '../../../import/domain/entities/sha256_result.dart';
import '../../../import/domain/services/file_hasher.dart';
import '../../../managed_copy/domain/entities/managed_file_ref.dart';
import '../../../managed_copy/domain/repositories/managed_copy_repository.dart';
import '../../../managed_copy/domain/services/documents_directory_resolver.dart';
import '../../domain/entities/export_batch_document_entry.dart';
import '../../domain/entities/export_category_entry.dart';
import '../../domain/entities/export_document_metadata.dart';
import '../../domain/entities/exportable_document_ref.dart';
import '../../domain/entities/generate_export_batch_result.dart';
import '../../domain/repositories/export_batch_repository.dart';
import '../../domain/services/export_filesystem.dart';

class _VerifiedDocument {
  const _VerifiedDocument({
    required this.documentCode,
    required this.documentId,
    required this.managedFileRef,
    required this.managedPath,
  });

  final String documentCode;
  final int documentId;
  final ManagedFileRef managedFileRef;
  final String managedPath;
}

class _ChecksumEntry {
  const _ChecksumEntry({required this.relativePath, required this.fullPath});

  final String relativePath;
  final String fullPath;
}

/// Orchestrates local export-batch generation
/// (workflow_and_validation_spec.md §11): verifies managed copies, stages a
/// batch folder, writes website-safe metadata, and self-verifies every
/// checksum before marking the batch `verified`.
///
/// Never mutates managed-library files. On any mid-way failure the batch
/// record is finalized `failed` and the partial export folder is left in
/// place for inspection — nothing is cleaned up automatically.
class GenerateExportBatch {
  GenerateExportBatch({
    required this.metadataRepository,
    required this.copyRepository,
    required this.batchRepository,
    required this.filesystem,
    required this.hasher,
    required this.clock,
    required this.documentsDirectoryResolver,
  });

  final DocumentMetadataRepository metadataRepository;
  final ManagedCopyRepository copyRepository;
  final ExportBatchRepository batchRepository;
  final ExportFilesystem filesystem;
  final FileHasher hasher;
  final Clock clock;
  final DocumentsDirectoryResolver documentsDirectoryResolver;

  Future<GenerateExportBatchResult> call() async {
    final String? exportRoot = await _resolveExportRoot();
    if (exportRoot == null) {
      return const GenerateExportBatchFailed(
        safeMessage: 'Could not resolve the export root.',
      );
    }

    final String? managedLibraryRoot =
        (await copyRepository.loadCopyRoots()).managedLibraryRoot;
    if (managedLibraryRoot == null) {
      return const GenerateExportBatchFailed(
        safeMessage: 'Managed library root is not configured.',
      );
    }

    final List<ExportableDocumentRef> readyDocs = await metadataRepository
        .listReadyForExport();
    if (readyDocs.isEmpty) {
      return const GenerateExportBatchNothingToExport();
    }

    final List<ExportSkipEntry> skipped = [];
    final List<_VerifiedDocument> verified = await _verifyManagedFiles(
      readyDocs,
      managedLibraryRoot,
      skipped,
    );
    if (verified.isEmpty) {
      return GenerateExportBatchAllSkipped(skippedReasons: skipped);
    }

    final DateTime now = clock.nowUtc();
    final String batchCode = await batchRepository.allocateBatchCode(now);
    final String folderName = _folderNameFor(batchCode);
    final String exportPath = _pathJoin(exportRoot, folderName);

    final int batchId = await batchRepository.createBatch(
      batchCode: batchCode,
      exportPath: exportPath,
      createdAt: now,
    );

    final String filesDir = _pathJoin(exportPath, 'files');
    final String metadataDir = _pathJoin(exportPath, 'metadata');

    final ExportFilesystemResult filesDirResult = await filesystem
        .ensureDirectoryExists(filesDir);
    final ExportFilesystemResult metadataDirResult = await filesystem
        .ensureDirectoryExists(metadataDir);
    if (filesDirResult is ExportFilesystemFailure) {
      return _fail(batchId, batchCode, exportPath, filesDirResult.safeMessage);
    }
    if (metadataDirResult is ExportFilesystemFailure) {
      return _fail(
        batchId,
        batchCode,
        exportPath,
        metadataDirResult.safeMessage,
      );
    }

    final List<_VerifiedDocument> copied = [];
    for (final _VerifiedDocument doc in verified) {
      final String dest = _pathJoin(filesDir, '${doc.documentCode}.pdf');
      final ExportFilesystemResult copyResult = await filesystem.copyFile(
        doc.managedPath,
        dest,
      );
      if (copyResult is ExportFilesystemFailure) {
        skipped.add(
          ExportSkipEntry(
            documentCode: doc.documentCode,
            reason: copyResult.safeMessage,
          ),
        );
        continue;
      }
      copied.add(doc);
    }
    if (copied.isEmpty) {
      return _fail(
        batchId,
        batchCode,
        exportPath,
        'No documents could be copied to the export folder.',
      );
    }

    final List<_VerifiedDocument> successList = [];
    for (final _VerifiedDocument doc in copied) {
      final String copyPath = _pathJoin(filesDir, '${doc.documentCode}.pdf');
      final Sha256Result hashResult = await _hash(copyPath);
      if (!hashResult.isSuccess ||
          hashResult.hash != doc.managedFileRef.sha256Hash) {
        skipped.add(
          ExportSkipEntry(
            documentCode: doc.documentCode,
            reason: 'export copy hash mismatch',
          ),
        );
        continue;
      }
      successList.add(doc);
    }
    if (successList.isEmpty) {
      return _fail(
        batchId,
        batchCode,
        exportPath,
        'No copied files could be verified.',
      );
    }

    await batchRepository.insertBatchDocuments(
      successList
          .map(
            (doc) => ExportBatchDocumentEntry(
              batchId: batchId,
              documentId: doc.documentId,
              managedFileId: doc.managedFileRef.fileId,
              sha256Hash: doc.managedFileRef.sha256Hash!,
              createdAt: now,
            ),
          )
          .toList(growable: false),
    );

    final List<int> successIds = successList
        .map((doc) => doc.documentId)
        .toList(growable: false);
    final List<ExportDocumentMetadata> metadata = await metadataRepository
        .loadExportMetadata(successIds);
    final List<ExportCategoryEntry> categories = await metadataRepository
        .loadExportCategories();
    final keywordsResult = await metadataRepository.loadExportKeywords(
      successIds,
    );

    final String documentsJson = jsonEncode(
      metadata.map(_metadataToJson).toList(growable: false),
    );
    final String documentsCsv = _buildCsv(metadata);
    final String categoriesJson = jsonEncode(
      categories.map(_categoryToJson).toList(growable: false),
    );
    final String keywordsJson = jsonEncode(
      keywordsResult.keywords
          .map((k) => {'keywordText': k.keywordText})
          .toList(growable: false),
    );
    final String documentKeywordsJson = jsonEncode(
      keywordsResult.documentKeywords
          .map(
            (dk) => {
              'documentCode': dk.documentCode,
              'keywordText': dk.keywordText,
            },
          )
          .toList(growable: false),
    );

    final ExportFilesystemFailure? writeFailure = await _writeAll(metadataDir, {
      'documents.json': documentsJson,
      'documents.csv': documentsCsv,
      'categories.json': categoriesJson,
      'keywords.json': keywordsJson,
      'document_keywords.json': documentKeywordsJson,
    });
    if (writeFailure != null) {
      return _fail(batchId, batchCode, exportPath, writeFailure.safeMessage);
    }

    int totalSizeBytes = 0;
    for (final _VerifiedDocument doc in successList) {
      final int? size = await filesystem.fileSize(
        _pathJoin(filesDir, '${doc.documentCode}.pdf'),
      );
      totalSizeBytes += size ?? 0;
    }

    final String manifestJson = jsonEncode({
      'batchCode': batchCode,
      'createdAt': now.toIso8601String(),
      'documentCount': successList.length,
      'totalSizeBytes': totalSizeBytes,
      'checksumAlgorithm': 'SHA-256',
      'documents': successList
          .map(
            (doc) => {
              'documentCode': doc.documentCode,
              'file': 'files/${doc.documentCode}.pdf',
              'sha256': doc.managedFileRef.sha256Hash,
            },
          )
          .toList(growable: false),
    });
    final String manifestPath = _pathJoin(exportPath, 'manifest.json');
    final ExportFilesystemResult manifestResult = await filesystem
        .writeTextFile(manifestPath, manifestJson);
    if (manifestResult is ExportFilesystemFailure) {
      return _fail(batchId, batchCode, exportPath, manifestResult.safeMessage);
    }

    final List<_ChecksumEntry> checksumEntries = [
      for (final doc in successList)
        _ChecksumEntry(
          relativePath: 'files/${doc.documentCode}.pdf',
          fullPath: _pathJoin(filesDir, '${doc.documentCode}.pdf'),
        ),
      _ChecksumEntry(
        relativePath: 'metadata/documents.json',
        fullPath: _pathJoin(metadataDir, 'documents.json'),
      ),
      _ChecksumEntry(
        relativePath: 'metadata/documents.csv',
        fullPath: _pathJoin(metadataDir, 'documents.csv'),
      ),
      _ChecksumEntry(
        relativePath: 'metadata/categories.json',
        fullPath: _pathJoin(metadataDir, 'categories.json'),
      ),
      _ChecksumEntry(
        relativePath: 'metadata/keywords.json',
        fullPath: _pathJoin(metadataDir, 'keywords.json'),
      ),
      _ChecksumEntry(
        relativePath: 'metadata/document_keywords.json',
        fullPath: _pathJoin(metadataDir, 'document_keywords.json'),
      ),
      _ChecksumEntry(relativePath: 'manifest.json', fullPath: manifestPath),
    ];

    final Map<String, String> recordedHashes = {};
    for (final _ChecksumEntry entry in checksumEntries) {
      final Sha256Result hashResult = await _hash(entry.fullPath);
      if (!hashResult.isSuccess) {
        return _fail(
          batchId,
          batchCode,
          exportPath,
          'Checksum computation failed.',
        );
      }
      recordedHashes[entry.relativePath] = hashResult.hash!;
    }

    final String checksumsContent = checksumEntries
        .map((e) => '${recordedHashes[e.relativePath]}  ${e.relativePath}')
        .join('\n');
    final String checksumsPath = _pathJoin(exportPath, 'checksums.sha256');
    final ExportFilesystemResult checksumsWriteResult = await filesystem
        .writeTextFile(checksumsPath, checksumsContent);
    if (checksumsWriteResult is ExportFilesystemFailure) {
      return _fail(
        batchId,
        batchCode,
        exportPath,
        checksumsWriteResult.safeMessage,
      );
    }

    final Set<String> successCodes = successList
        .map((doc) => doc.documentCode)
        .toSet();
    final List<ExportFlaggedEntry> flagged = metadata
        .where(
          (m) =>
              m.isUsageRightsFlagged && successCodes.contains(m.documentCode),
        )
        .map(
          (m) => ExportFlaggedEntry(
            documentCode: m.documentCode,
            usageRightsKey: m.usageRightsKey,
          ),
        )
        .toList(growable: false);

    final String reportJson = jsonEncode({
      'batchCode': batchCode,
      'generatedAt': now.toIso8601String(),
      'includedCount': successList.length,
      'skippedCount': skipped.length,
      'skipped': skipped
          .map((s) => {'documentCode': s.documentCode, 'reason': s.reason})
          .toList(growable: false),
      'flaggedUsageRights': flagged
          .map(
            (f) => {
              'documentCode': f.documentCode,
              'usageRightsKey': f.usageRightsKey,
            },
          )
          .toList(growable: false),
    });
    final ExportFilesystemResult reportResult = await filesystem.writeTextFile(
      _pathJoin(exportPath, 'export_report.json'),
      reportJson,
    );
    if (reportResult is ExportFilesystemFailure) {
      return _fail(batchId, batchCode, exportPath, reportResult.safeMessage);
    }

    for (final _ChecksumEntry entry in checksumEntries) {
      final Sha256Result verifyResult = await _hash(entry.fullPath);
      if (!verifyResult.isSuccess ||
          verifyResult.hash != recordedHashes[entry.relativePath]) {
        return _fail(
          batchId,
          batchCode,
          exportPath,
          'Export verification failed: checksum mismatch.',
        );
      }
    }

    final DateTime completedAt = clock.nowUtc();
    await batchRepository.finalizeBatch(
      batchId: batchId,
      statusKey: 'verified',
      documentCount: successList.length,
      totalSizeBytes: totalSizeBytes,
      completedAt: completedAt,
    );

    return GenerateExportBatchSuccess(
      batchCode: batchCode,
      exportPath: exportPath,
      includedCount: successList.length,
      skippedCount: skipped.length,
      skippedReasons: skipped,
      flaggedUsageRights: flagged,
    );
  }

  Future<String?> _resolveExportRoot() async {
    final String? configured = await copyRepository.loadExportRoot();
    if (configured != null) return configured;

    String? documentsPath;
    try {
      documentsPath = await documentsDirectoryResolver.resolveDocumentsPath();
    } catch (_) {
      documentsPath = null;
    }
    if (documentsPath == null) return null;
    return _pathJoin(_pathJoin(documentsPath, 'MARJIY'), 'Exports');
  }

  Future<List<_VerifiedDocument>> _verifyManagedFiles(
    List<ExportableDocumentRef> readyDocs,
    String managedLibraryRoot,
    List<ExportSkipEntry> skipped,
  ) async {
    final List<_VerifiedDocument> verified = [];
    for (final ExportableDocumentRef doc in readyDocs) {
      final List<ManagedFileRef> files = await copyRepository
          .loadManagedCopyFiles(doc.id);
      final Iterable<ManagedFileRef> healthy = files.where(
        (f) => f.fileHealthKey == 'healthy',
      );
      if (healthy.isEmpty) {
        skipped.add(
          ExportSkipEntry(
            documentCode: doc.documentCode,
            reason: 'no healthy managed copy',
          ),
        );
        continue;
      }
      final ManagedFileRef managedFile = healthy.first;

      final String expectedPath = _pathJoin(
        _pathJoin(managedLibraryRoot, 'files'),
        '${doc.documentCode}.pdf',
      );
      if (!filesystem.isExistingFile(expectedPath)) {
        skipped.add(
          ExportSkipEntry(
            documentCode: doc.documentCode,
            reason: 'managed file not found on disk',
          ),
        );
        continue;
      }

      final Sha256Result hashResult = await _hash(expectedPath);
      if (!hashResult.isSuccess) {
        skipped.add(
          ExportSkipEntry(
            documentCode: doc.documentCode,
            reason: 'hash computation failed',
          ),
        );
        continue;
      }
      if (hashResult.hash != managedFile.sha256Hash) {
        skipped.add(
          ExportSkipEntry(
            documentCode: doc.documentCode,
            reason: 'managed file hash mismatch',
          ),
        );
        continue;
      }

      verified.add(
        _VerifiedDocument(
          documentCode: doc.documentCode,
          documentId: doc.id,
          managedFileRef: managedFile,
          managedPath: expectedPath,
        ),
      );
    }
    return verified;
  }

  Future<Sha256Result> _hash(String path) => hasher.hashFile(path);

  Future<ExportFilesystemFailure?> _writeAll(
    String dir,
    Map<String, String> filesByName,
  ) async {
    for (final entry in filesByName.entries) {
      final result = await filesystem.writeTextFile(
        _pathJoin(dir, entry.key),
        entry.value,
      );
      if (result is ExportFilesystemFailure) return result;
    }
    return null;
  }

  Future<GenerateExportBatchFailed> _fail(
    int batchId,
    String batchCode,
    String exportPath,
    String safeMessage,
  ) async {
    await batchRepository.finalizeBatch(
      batchId: batchId,
      statusKey: 'failed',
      documentCount: 0,
      totalSizeBytes: 0,
      completedAt: clock.nowUtc(),
    );
    return GenerateExportBatchFailed(
      safeMessage: safeMessage,
      batchCode: batchCode,
      exportPath: exportPath,
    );
  }

  static String _folderNameFor(String batchCode) {
    final String suffix = batchCode.substring('EXP-'.length);
    return 'export_batch_${suffix.replaceAll('-', '_')}';
  }

  static String _pathJoin(String base, String part) {
    final String normalizedBase = base.replaceAll('/', r'\');
    final String trimmed = normalizedBase.endsWith(r'\')
        ? normalizedBase.substring(0, normalizedBase.length - 1)
        : normalizedBase;
    return '$trimmed\\$part';
  }

  static Map<String, dynamic> _metadataToJson(ExportDocumentMetadata m) => {
    'documentCode': m.documentCode,
    'titleAr': m.titleAr,
    'titleEn': m.titleEn,
    'documentTypeKey': m.documentTypeKey,
    'documentTypeNameAr': m.documentTypeNameAr,
    'documentTypeNameEn': m.documentTypeNameEn,
    'primaryMainCategoryKey': m.primaryMainCategoryKey,
    'primaryMainCategoryNameAr': m.primaryMainCategoryNameAr,
    'primaryMainCategoryNameEn': m.primaryMainCategoryNameEn,
    'primarySubcategoryKey': m.primarySubcategoryKey,
    'primarySubcategoryNameAr': m.primarySubcategoryNameAr,
    'primarySubcategoryNameEn': m.primarySubcategoryNameEn,
    'countryCode': m.countryCode,
    'countryNameAr': m.countryNameAr,
    'countryNameEn': m.countryNameEn,
    'languageKey': m.languageKey,
    'languageNameAr': m.languageNameAr,
    'languageNameEn': m.languageNameEn,
    'languageOther': m.languageOther,
    'trustLevelKey': m.trustLevelKey,
    'usageRightsKey': m.usageRightsKey,
    'isUsageRightsFlagged': m.isUsageRightsFlagged,
    'metadataQualityKey': m.metadataQualityKey,
    'summaryAr': m.summaryAr,
    'readyForExportAt': m.readyForExportAt.toIso8601String(),
    'keywords': m.keywords,
    'legislationDetails': m.legislationDetails == null
        ? null
        : {
            'legislationNumber': m.legislationDetails!.legislationNumber,
            'legislationYear': m.legislationDetails!.legislationYear,
            'effectiveDate': m.legislationDetails!.effectiveDate,
            'repealDate': m.legislationDetails!.repealDate,
            'effectiveStatusKey': m.legislationDetails!.effectiveStatusKey,
            'legislationTypeKey': m.legislationDetails!.legislationTypeKey,
            'legislationTypeOther': m.legislationDetails!.legislationTypeOther,
          },
    'legislationRelations': m.legislationRelations
        .map(
          (r) => {
            'targetDocumentCode': r.targetDocumentCode,
            'relationTypeKey': r.relationTypeKey,
            'scope': r.scope,
            'effectiveDate': r.effectiveDate,
            'notes': r.notes,
          },
        )
        .toList(growable: false),
  };

  static Map<String, dynamic> _categoryToJson(ExportCategoryEntry c) => {
    'mainCategoryKey': c.mainCategoryKey,
    'mainCategoryNameAr': c.mainCategoryNameAr,
    'mainCategoryNameEn': c.mainCategoryNameEn,
    'sortOrder': c.sortOrder,
    'subcategories': c.subcategories
        .map(
          (s) => {
            'subcategoryKey': s.subcategoryKey,
            'subcategoryNameAr': s.subcategoryNameAr,
            'subcategoryNameEn': s.subcategoryNameEn,
            'sortOrder': s.sortOrder,
          },
        )
        .toList(growable: false),
  };

  static String _buildCsv(List<ExportDocumentMetadata> metadata) {
    const List<String> header = [
      'document_code',
      'title_ar',
      'title_en',
      'document_type_key',
      'document_type_name_ar',
      'document_type_name_en',
      'primary_main_category_key',
      'primary_main_category_name_ar',
      'primary_main_category_name_en',
      'primary_subcategory_key',
      'primary_subcategory_name_ar',
      'primary_subcategory_name_en',
      'country_code',
      'country_name_ar',
      'country_name_en',
      'language_key',
      'language_name_ar',
      'language_name_en',
      'language_other',
      'trust_level_key',
      'usage_rights_key',
      'is_usage_rights_flagged',
      'metadata_quality_key',
      'summary_ar',
      'ready_for_export_at',
      'keywords',
      'legislation_number',
      'legislation_year',
      'legislation_effective_date',
      'legislation_repeal_date',
      'legislation_effective_status_key',
      'legislation_type_key',
      'legislation_type_other',
    ];

    final List<String> lines = [header.map(_csvField).join(',')];
    for (final ExportDocumentMetadata m in metadata) {
      final row = [
        m.documentCode,
        m.titleAr ?? '',
        m.titleEn ?? '',
        m.documentTypeKey,
        m.documentTypeNameAr,
        m.documentTypeNameEn,
        m.primaryMainCategoryKey,
        m.primaryMainCategoryNameAr,
        m.primaryMainCategoryNameEn,
        m.primarySubcategoryKey ?? '',
        m.primarySubcategoryNameAr ?? '',
        m.primarySubcategoryNameEn ?? '',
        m.countryCode ?? '',
        m.countryNameAr ?? '',
        m.countryNameEn ?? '',
        m.languageKey ?? '',
        m.languageNameAr ?? '',
        m.languageNameEn ?? '',
        m.languageOther ?? '',
        m.trustLevelKey,
        m.usageRightsKey,
        m.isUsageRightsFlagged.toString(),
        m.metadataQualityKey,
        m.summaryAr ?? '',
        m.readyForExportAt.toIso8601String(),
        m.keywords.join(';'),
        m.legislationDetails?.legislationNumber ?? '',
        m.legislationDetails?.legislationYear ?? '',
        m.legislationDetails?.effectiveDate ?? '',
        m.legislationDetails?.repealDate ?? '',
        m.legislationDetails?.effectiveStatusKey ?? '',
        m.legislationDetails?.legislationTypeKey ?? '',
        m.legislationDetails?.legislationTypeOther ?? '',
      ];
      lines.add(row.map(_csvField).join(','));
    }
    return lines.join('\n');
  }

  static String _csvField(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
