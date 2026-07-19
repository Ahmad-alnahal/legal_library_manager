// test/features/export/application/use_cases/generate_export_batch_test.dart

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_aggregate.dart';
import 'package:legal_library_manager/features/documents/domain/entities/normalized_draft.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_metadata_repository.dart';
import 'package:legal_library_manager/features/export/application/use_cases/generate_export_batch.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_batch_document_entry.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_batch_summary.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_category_entry.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_document_metadata.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_eligibility_result.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_keywords_result.dart';
import 'package:legal_library_manager/features/export/domain/entities/exportable_document_ref.dart';
import 'package:legal_library_manager/features/export/domain/entities/generate_export_batch_result.dart';
import 'package:legal_library_manager/features/export/domain/repositories/export_batch_repository.dart';
import 'package:legal_library_manager/features/export/domain/services/export_filesystem.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/document_copy_state.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_persistence_data.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_file_ref.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/source_file_candidate.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/documents_directory_resolver.dart';

String _hex(String key) => sha256.convert(utf8.encode(key)).toString();

class _FixedClock extends Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

class _FakeDocumentsDirectoryResolver implements DocumentsDirectoryResolver {
  String? pathToReturn;

  @override
  Future<String?> resolveDocumentsPath() async => pathToReturn;
}

class _FakeMetadataRepository implements DocumentMetadataRepository {
  List<ExportableDocumentRef> readyDocs = const [];
  List<ExportDocumentMetadata> metadataToReturn = const [];
  List<ExportCategoryEntry> categoriesToReturn = const [];
  ExportKeywordsResult keywordsToReturn = const ExportKeywordsResult(
    keywords: [],
    documentKeywords: [],
  );
  List<int>? lastLoadExportMetadataIds;
  List<int>? lastLoadExportKeywordsIds;

  @override
  Future<List<ExportableDocumentRef>> listReadyForExport() =>
      Future.value(readyDocs);

  @override
  Future<List<ExportDocumentMetadata>> loadExportMetadata(
    List<int> documentIds,
  ) {
    lastLoadExportMetadataIds = documentIds;
    return Future.value(metadataToReturn);
  }

  @override
  Future<List<ExportCategoryEntry>> loadExportCategories() =>
      Future.value(categoriesToReturn);

  @override
  Future<ExportKeywordsResult> loadExportKeywords(List<int> documentIds) {
    lastLoadExportKeywordsIds = documentIds;
    return Future.value(keywordsToReturn);
  }

  @override
  Future<ExportEligibilityResult> checkExportEligibility(int documentId) =>
      throw UnimplementedError();

  @override
  Future<void> markReadyForExport(int documentId, {required DateTime now}) =>
      throw UnimplementedError();

  @override
  Future<DocumentAggregate?> loadAggregate(int documentId) =>
      throw UnimplementedError();

  @override
  Future<void> saveDraft(
    NormalizedDraft draft, {
    required DateTime now,
    required String workflowStatusKey,
    required bool clearClassifiedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> markClassified(int documentId, {required DateTime now}) =>
      throw UnimplementedError();

  @override
  Future<void> returnToInProgress(int documentId, {required DateTime now}) =>
      throw UnimplementedError();
}

class _FakeManagedCopyRepository implements ManagedCopyRepository {
  CopyRoots copyRoots = const CopyRoots();
  String? exportRoot;
  Map<int, List<ManagedFileRef>> managedFilesByDocId = {};

  @override
  Future<CopyRoots> loadCopyRoots() => Future.value(copyRoots);

  @override
  Future<String?> loadExportRoot() => Future.value(exportRoot);

  @override
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId) =>
      Future.value(managedFilesByDocId[documentId] ?? const []);

  @override
  Future<DocumentCopyState?> loadDocumentState(int documentId) =>
      throw UnimplementedError();

  @override
  Future<void> saveExportRoot(String path) => throw UnimplementedError();

  @override
  Future<String> loadDatabaseRoot() => throw UnimplementedError();

  @override
  Future<String> loadWordTempRoot() => throw UnimplementedError();

  @override
  Future<List<String>> loadDocumentSourcePaths(int documentId) =>
      throw UnimplementedError();

  @override
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId) =>
      throw UnimplementedError();

  @override
  Future<String> allocateDocumentCode(int documentId) =>
      throw UnimplementedError();

  @override
  Future<void> appendFileEvent({
    required int? documentId,
    required int? fileId,
    required String eventTypeKey,
    required String operationId,
    required String resultKey,
    String? sourcePath,
    String? destinationPath,
    String? expectedSha256,
    String? actualSha256,
    String? errorCode,
    String? messageSafe,
  }) => throw UnimplementedError();

  @override
  Future<int> persistManagedCopySuccess(ManagedCopyPersistenceData data) =>
      throw UnimplementedError();

  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) => throw UnimplementedError();

  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) => throw UnimplementedError();

  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) => throw UnimplementedError();

  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> loadAllSourcePaths() => throw UnimplementedError();

  @override
  Future<List<String>> loadManagedDocumentCodes() => throw UnimplementedError();

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) =>
      throw UnimplementedError();

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() =>
      throw UnimplementedError();

  @override
  Future<List<ManagedFileRef>> loadAllManagedCopyFiles() =>
      throw UnimplementedError();

  @override
  Future<List<int>> loadCopiedToLibraryDocumentIds() =>
      throw UnimplementedError();

  @override
  Future<List<({int documentId, String workflowStatusKey})>>
  loadDocumentsWithStaleDocumentCode() => throw UnimplementedError();

  @override
  Future<void> markManagedFileCorrupted({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) => throw UnimplementedError();
}

class _FakeExportBatchRepository implements ExportBatchRepository {
  String batchCodeToReturn = 'EXP-2026-07-18-001';
  int batchIdToReturn = 1;

  final List<Map<String, Object?>> createBatchCalls = [];
  final List<List<ExportBatchDocumentEntry>> insertBatchDocumentsCalls = [];
  final List<Map<String, Object?>> finalizeBatchCalls = [];

  @override
  Future<String> allocateBatchCode(DateTime now) =>
      Future.value(batchCodeToReturn);

  @override
  Future<int> createBatch({
    required String batchCode,
    required String exportPath,
    required DateTime createdAt,
  }) {
    createBatchCalls.add({
      'batchCode': batchCode,
      'exportPath': exportPath,
      'createdAt': createdAt,
    });
    return Future.value(batchIdToReturn);
  }

  @override
  Future<void> insertBatchDocuments(List<ExportBatchDocumentEntry> entries) {
    insertBatchDocumentsCalls.add(entries);
    return Future.value();
  }

  @override
  Future<void> finalizeBatch({
    required int batchId,
    required String statusKey,
    required int documentCount,
    required int totalSizeBytes,
    required DateTime completedAt,
  }) {
    finalizeBatchCalls.add({
      'batchId': batchId,
      'statusKey': statusKey,
      'documentCount': documentCount,
      'totalSizeBytes': totalSizeBytes,
      'completedAt': completedAt,
    });
    return Future.value();
  }

  @override
  Future<List<ExportBatchSummary>> listBatches() => throw UnimplementedError();
}

class _FakeExportFilesystem implements ExportFilesystem {
  final Set<String> existingFiles = {};
  final Map<String, String> writtenFiles = {};
  final List<String> copiedDestPaths = [];
  final Set<String> failCopyDestPaths = {};
  final Set<String> failWritePaths = {};

  @override
  Future<ExportFilesystemResult> ensureDirectoryExists(String dirPath) async =>
      const ExportFilesystemSuccess();

  @override
  Future<ExportFilesystemResult> copyFile(
    String sourcePath,
    String destPath,
  ) async {
    if (failCopyDestPaths.contains(destPath)) {
      return const ExportFilesystemFailure(safeMessage: 'File copy failed.');
    }
    copiedDestPaths.add(destPath);
    existingFiles.add(destPath);
    return const ExportFilesystemSuccess();
  }

  @override
  Future<ExportFilesystemResult> writeTextFile(
    String filePath,
    String content,
  ) async {
    if (failWritePaths.contains(filePath)) {
      return const ExportFilesystemFailure(safeMessage: 'File write failed.');
    }
    writtenFiles[filePath] = content;
    existingFiles.add(filePath);
    return const ExportFilesystemSuccess();
  }

  @override
  Future<int?> fileSize(String path) async => 1000;

  @override
  bool isExistingFile(String path) => existingFiles.contains(path);
}

class _FakeFileHasher implements FileHasher {
  final Map<String, List<String>> sequencedHashes = {};
  final Set<String> failPaths = {};
  final List<String> calls = [];

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    calls.add(absolutePath);
    if (failPaths.contains(absolutePath)) {
      return Sha256Result.failure(
        const ImportError(code: ImportErrorCode.hashFailed),
      );
    }
    final List<String>? queue = sequencedHashes[absolutePath];
    if (queue != null && queue.isNotEmpty) {
      return Sha256Result.success(queue.removeAt(0));
    }
    return Sha256Result.success(_hex(absolutePath));
  }
}

void main() {
  const String managedRoot = r'C:\Managed';
  const String exportRoot = r'C:\Export';
  const String batchCode = 'EXP-2026-07-18-001';
  const String exportPath = r'C:\Export\export_batch_2026_07_18_001';
  const String filesDir = '$exportPath\\files';
  const String metadataDir = '$exportPath\\metadata';

  late _FakeMetadataRepository metadataRepository;
  late _FakeManagedCopyRepository copyRepository;
  late _FakeExportBatchRepository batchRepository;
  late _FakeExportFilesystem filesystem;
  late _FakeFileHasher hasher;
  late _FakeDocumentsDirectoryResolver documentsDirectoryResolver;
  late _FixedClock clock;
  late GenerateExportBatch useCase;

  ExportDocumentMetadata metadataFor(
    String documentCode, {
    bool flagged = false,
  }) {
    return ExportDocumentMetadata(
      documentCode: documentCode,
      titleAr: 'عنوان',
      titleEn: 'Title',
      documentTypeKey: 'law',
      documentTypeNameAr: 'قانون',
      documentTypeNameEn: 'Law',
      primaryMainCategoryKey: 'main',
      primaryMainCategoryNameAr: 'رئيسي',
      primaryMainCategoryNameEn: 'Main',
      primarySubcategoryKey: null,
      primarySubcategoryNameAr: null,
      primarySubcategoryNameEn: null,
      countryCode: 'EG',
      countryNameAr: 'مصر',
      countryNameEn: 'Egypt',
      languageKey: 'ar',
      languageNameAr: 'عربي',
      languageNameEn: 'Arabic',
      trustLevelKey: 'official',
      usageRightsKey: flagged ? 'personal_use_only' : 'public',
      isUsageRightsFlagged: flagged,
      metadataQualityKey: 'high',
      summaryAr: 'ملخص',
      readyForExportAt: DateTime.utc(2026, 7, 17),
      keywords: const ['keyword-a'],
      legislationDetails: null,
      legislationRelations: const [],
    );
  }

  void setUpHealthyDocument({
    required int documentId,
    required String documentCode,
  }) {
    final String hash = _hex(documentCode);
    final String managedPath = '$managedRoot\\files\\$documentCode.pdf';
    final String copyPath = '$filesDir\\$documentCode.pdf';

    copyRepository.managedFilesByDocId[documentId] = [
      ManagedFileRef(
        fileId: documentId * 10,
        documentId: documentId,
        absolutePath: managedPath,
        fileHealthKey: 'healthy',
        fileSizeBytes: 1000,
        sha256Hash: hash,
      ),
    ];
    filesystem.existingFiles.add(managedPath);
    hasher.sequencedHashes[managedPath] = [hash];
    hasher.sequencedHashes[copyPath] = [hash];
  }

  setUp(() {
    metadataRepository = _FakeMetadataRepository();
    copyRepository = _FakeManagedCopyRepository()
      ..copyRoots = const CopyRoots(managedLibraryRoot: managedRoot)
      ..exportRoot = exportRoot;
    batchRepository = _FakeExportBatchRepository()
      ..batchCodeToReturn = batchCode
      ..batchIdToReturn = 1;
    filesystem = _FakeExportFilesystem();
    hasher = _FakeFileHasher();
    documentsDirectoryResolver = _FakeDocumentsDirectoryResolver();
    clock = _FixedClock(DateTime.utc(2026, 7, 18, 12));
    useCase = GenerateExportBatch(
      metadataRepository: metadataRepository,
      copyRepository: copyRepository,
      batchRepository: batchRepository,
      filesystem: filesystem,
      hasher: hasher,
      clock: clock,
      documentsDirectoryResolver: documentsDirectoryResolver,
    );
  });

  test('nothingToExport: no ready documents', () async {
    metadataRepository.readyDocs = const [];

    final result = await useCase.call();

    expect(result, isA<GenerateExportBatchNothingToExport>());
    expect(batchRepository.createBatchCalls, isEmpty);
  });

  test(
    'allSkipped: all ready documents fail managed-file verification',
    () async {
      metadataRepository.readyDocs = [
        ExportableDocumentRef(
          id: 1,
          documentCode: 'DOC-0000001',
          readyForExportAt: DateTime.utc(2026, 7, 17),
        ),
      ];
      // No managed_copy files registered for document 1 at all.

      final result = await useCase.call();

      expect(result, isA<GenerateExportBatchAllSkipped>());
      final skipped = (result as GenerateExportBatchAllSkipped).skippedReasons;
      expect(skipped, [
        const ExportSkipEntry(
          documentCode: 'DOC-0000001',
          reason: 'no healthy managed copy',
        ),
      ]);
      expect(batchRepository.createBatchCalls, isEmpty);
    },
  );

  test('noManagedRoot: fails immediately without creating a batch', () async {
    copyRepository.copyRoots = const CopyRoots();

    final result = await useCase.call();

    expect(result, isA<GenerateExportBatchFailed>());
    final failed = result as GenerateExportBatchFailed;
    expect(failed.batchCode, isNull);
    expect(failed.exportPath, isNull);
    expect(batchRepository.createBatchCalls, isEmpty);
  });

  test('happyPath: two verified documents produce a verified batch', () async {
    metadataRepository.readyDocs = [
      ExportableDocumentRef(
        id: 1,
        documentCode: 'DOC-0000001',
        readyForExportAt: DateTime.utc(2026, 7, 17),
      ),
      ExportableDocumentRef(
        id: 2,
        documentCode: 'DOC-0000002',
        readyForExportAt: DateTime.utc(2026, 7, 17),
      ),
    ];
    setUpHealthyDocument(documentId: 1, documentCode: 'DOC-0000001');
    setUpHealthyDocument(documentId: 2, documentCode: 'DOC-0000002');
    metadataRepository.metadataToReturn = [
      metadataFor('DOC-0000001'),
      metadataFor('DOC-0000002'),
    ];

    final result = await useCase.call();

    expect(result, isA<GenerateExportBatchSuccess>());
    final success = result as GenerateExportBatchSuccess;
    expect(success.batchCode, batchCode);
    expect(success.exportPath, exportPath);
    expect(success.includedCount, 2);
    expect(success.skippedCount, 0);
    expect(success.skippedReasons, isEmpty);
    expect(success.flaggedUsageRights, isEmpty);

    expect(batchRepository.createBatchCalls, hasLength(1));
    expect(batchRepository.insertBatchDocumentsCalls.single, hasLength(2));
    expect(batchRepository.finalizeBatchCalls, hasLength(1));
    expect(batchRepository.finalizeBatchCalls.single['statusKey'], 'verified');
    expect(batchRepository.finalizeBatchCalls.single['documentCount'], 2);

    expect(filesystem.copiedDestPaths, [
      '$filesDir\\DOC-0000001.pdf',
      '$filesDir\\DOC-0000002.pdf',
    ]);
    expect(
      filesystem.writtenFiles.containsKey('$metadataDir\\documents.json'),
      isTrue,
    );
    expect(
      filesystem.writtenFiles.containsKey('$metadataDir\\documents.csv'),
      isTrue,
    );
    expect(
      filesystem.writtenFiles.containsKey('$metadataDir\\categories.json'),
      isTrue,
    );
    expect(
      filesystem.writtenFiles.containsKey('$metadataDir\\keywords.json'),
      isTrue,
    );
    expect(
      filesystem.writtenFiles.containsKey(
        '$metadataDir\\document_keywords.json',
      ),
      isTrue,
    );
    expect(
      filesystem.writtenFiles.containsKey('$exportPath\\manifest.json'),
      isTrue,
    );
    expect(
      filesystem.writtenFiles.containsKey('$exportPath\\checksums.sha256'),
      isTrue,
    );
    expect(
      filesystem.writtenFiles.containsKey('$exportPath\\export_report.json'),
      isTrue,
    );

    final manifest =
        jsonDecode(filesystem.writtenFiles['$exportPath\\manifest.json']!)
            as Map<String, dynamic>;
    expect(manifest['documentCount'], 2);
    expect((manifest['documents'] as List).length, 2);
  });

  test('partialSkip: one document copies, one fails copy', () async {
    metadataRepository.readyDocs = [
      ExportableDocumentRef(
        id: 1,
        documentCode: 'DOC-0000001',
        readyForExportAt: DateTime.utc(2026, 7, 17),
      ),
      ExportableDocumentRef(
        id: 2,
        documentCode: 'DOC-0000002',
        readyForExportAt: DateTime.utc(2026, 7, 17),
      ),
    ];
    setUpHealthyDocument(documentId: 1, documentCode: 'DOC-0000001');
    setUpHealthyDocument(documentId: 2, documentCode: 'DOC-0000002');
    filesystem.failCopyDestPaths.add('$filesDir\\DOC-0000002.pdf');
    metadataRepository.metadataToReturn = [metadataFor('DOC-0000001')];

    final result = await useCase.call();

    expect(result, isA<GenerateExportBatchSuccess>());
    final success = result as GenerateExportBatchSuccess;
    expect(success.includedCount, 1);
    expect(success.skippedCount, 1);
    expect(success.skippedReasons, [
      const ExportSkipEntry(
        documentCode: 'DOC-0000002',
        reason: 'File copy failed.',
      ),
    ]);
  });

  test('flaggedUsageRights: a personal_use_only document is flagged', () async {
    metadataRepository.readyDocs = [
      ExportableDocumentRef(
        id: 1,
        documentCode: 'DOC-0000001',
        readyForExportAt: DateTime.utc(2026, 7, 17),
      ),
    ];
    setUpHealthyDocument(documentId: 1, documentCode: 'DOC-0000001');
    metadataRepository.metadataToReturn = [
      metadataFor('DOC-0000001', flagged: true),
    ];

    final result = await useCase.call();

    expect(result, isA<GenerateExportBatchSuccess>());
    final success = result as GenerateExportBatchSuccess;
    expect(success.flaggedUsageRights, [
      const ExportFlaggedEntry(
        documentCode: 'DOC-0000001',
        usageRightsKey: 'personal_use_only',
      ),
    ]);

    final report =
        jsonDecode(filesystem.writtenFiles['$exportPath\\export_report.json']!)
            as Map<String, dynamic>;
    expect((report['flaggedUsageRights'] as List).single, {
      'documentCode': 'DOC-0000001',
      'usageRightsKey': 'personal_use_only',
    });
  });

  test(
    'checksumMismatch: verification detects a mismatch and fails the batch',
    () async {
      metadataRepository.readyDocs = [
        ExportableDocumentRef(
          id: 1,
          documentCode: 'DOC-0000001',
          readyForExportAt: DateTime.utc(2026, 7, 17),
        ),
      ];
      setUpHealthyDocument(documentId: 1, documentCode: 'DOC-0000001');
      metadataRepository.metadataToReturn = [metadataFor('DOC-0000001')];
      // First hash call (checksums build) returns one value, the second
      // (self-verification re-hash) returns a different one.
      hasher.sequencedHashes['$metadataDir\\documents.json'] = [
        _hex('first'),
        _hex('second'),
      ];

      final result = await useCase.call();

      expect(result, isA<GenerateExportBatchFailed>());
      final failed = result as GenerateExportBatchFailed;
      expect(failed.batchCode, batchCode);
      expect(failed.exportPath, exportPath);
      expect(batchRepository.finalizeBatchCalls, hasLength(1));
      expect(batchRepository.finalizeBatchCalls.single['statusKey'], 'failed');
    },
  );
}
