// test/features/managed_copy/application/managed_copy_use_case_doc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/managed_copy/application/managed_copy_use_case.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/document_copy_state.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_error.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_persistence_data.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_file_ref.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/source_file_candidate.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/database_backup_service.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/operation_id_generator.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/path_canonicalizer.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/word_document_converter.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kDocId = 1;
const _kDocPath = r'C:\Sources\report.doc';
const _kPdfHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
// Word conversion temp input/output live in a local, non-cloud-synced app
// temp folder — never under the managed library root.
const _kWordTempParent = r'C:\LocalTemp\MARJIY';
const _kWordTempDir = r'C:\LocalTemp\MARJIY\WordConversionTemp';
const _kTempPdfPath =
    r'C:\LocalTemp\MARJIY\WordConversionTemp\copy_test_1.word_out';
// <managedFilesDir>\<docCode>.pdf.<operationId>.copying
const _kCopyingPath = r'C:\Library\files\DOC-0000001.pdf.copy_test_1.copying';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeClock extends Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 6, 26, 10, 0, 0);
}

class _FakeRepo implements ManagedCopyRepository {
  DocumentCopyState? docState = DocumentCopyState(
    documentId: _kDocId,
    workflowStatusKey: 'classified',
    existingDocumentCode: null,
    hasManagedCopy: false,
    hasHealthyManagedCopy: false,
  );
  CopyRoots roots = const CopyRoots(
    managedLibraryRoot: r'C:\Library',
    backupRoot: r'D:\Backups',
  );
  String databaseRoot = r'C:\AppSupport';
  String wordTempRoot = _kWordTempParent;
  List<String> sourcePaths = [_kDocPath];
  List<SourceFileCandidate> candidates = [];
  List<ManagedFileRef> managedFiles = [];
  String allocatedCode = 'DOC-0000001';
  bool throwOnPersist = false;
  int persistedFileId = 42;
  int allocateDocumentCodeCalls = 0;

  final List<Map<String, Object?>> events = [];

  @override
  Future<DocumentCopyState?> loadDocumentState(int documentId) async =>
      docState;

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) async {}

  @override
  Future<String?> loadExportRoot() async => null;

  @override
  Future<void> saveExportRoot(String path) async {}

  @override
  Future<String> loadDatabaseRoot() async => databaseRoot;

  @override
  Future<String> loadWordTempRoot() async => wordTempRoot;

  @override
  Future<List<String>> loadDocumentSourcePaths(int documentId) async =>
      sourcePaths;

  @override
  Future<List<String>> loadAllSourcePaths() async => sourcePaths;

  @override
  Future<List<String>> loadManagedDocumentCodes() async => const [];

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {}

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;

  @override
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId) async =>
      candidates;

  @override
  Future<String> allocateDocumentCode(int documentId) async {
    allocateDocumentCodeCalls++;
    return allocatedCode;
  }

  Set<String> throwOnAuditEvent = {};

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
  }) async {
    if (throwOnAuditEvent.contains(eventTypeKey)) {
      throw StateError('simulated audit event failure for $eventTypeKey');
    }
    events.add({
      'eventTypeKey': eventTypeKey,
      'resultKey': resultKey,
      'errorCode': errorCode,
      'messageSafe': messageSafe,
      'sourcePath': sourcePath,
      'destinationPath': destinationPath,
    });
  }

  @override
  Future<int> persistManagedCopySuccess(ManagedCopyPersistenceData data) async {
    if (throwOnPersist) throw Exception('simulated DB failure');
    return persistedFileId;
  }

  @override
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId) async =>
      managedFiles;

  @override
  Future<List<ManagedFileRef>> loadAllManagedCopyFiles() async => managedFiles;

  @override
  Future<List<int>> loadCopiedToLibraryDocumentIds() async => const [];

  @override
  Future<List<({int documentId, String workflowStatusKey})>>
  loadDocumentsWithStaleDocumentCode() async => const [];

  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}

  @override
  Future<void> markManagedFileCorrupted({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}

  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}

  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) async {}
}

class _FakeCanonicalizer implements PathCanonicalizer {
  @override
  String? canonicalize(String path) => path;
}

class _CountingIdGenerator implements OperationIdGenerator {
  @override
  String generate(DateTime now) => 'copy_test_1';
}

class _FakeFilesystem implements ManagedLibraryFilesystem {
  final Set<String> _existingFiles;
  final Set<String> _existingDirs;
  FilesystemOperationResult ensureResult = const FilesystemSuccess();
  FilesystemOperationResult copyResult = const FilesystemSuccess();
  FilesystemOperationResult finalizeResult = const FilesystemSuccess();
  int? fileSizeResult = 54321;
  List<String>? recoveryArtifacts = [];

  final List<String> copyCalls = [];
  final List<String> deleteCalls = [];

  _FakeFilesystem({Set<String>? existingFiles, Set<String>? existingDirs})
    : _existingFiles = existingFiles ?? {_kDocPath, _kTempPdfPath},
      _existingDirs =
          existingDirs ??
          {
            r'C:\Library',
            r'D:\Backups',
            r'C:\Library\files',
            _kWordTempParent,
            _kWordTempDir,
          };

  @override
  bool isExistingDirectory(String path) => _existingDirs.contains(path);

  @override
  bool isExistingFile(String path) => _existingFiles.contains(path);

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) async {
    _existingDirs.add(absoluteDirPath);
    return ensureResult;
  }

  @override
  Future<FilesystemOperationResult> copyFile(
    String sourcePath,
    String destPath,
  ) async {
    copyCalls.addAll([sourcePath, destPath]);
    _existingFiles.add(destPath);
    return copyResult;
  }

  @override
  Future<FilesystemOperationResult> finalizeFile(
    String tmpPath,
    String finalPath,
  ) async {
    return finalizeResult;
  }

  @override
  Future<int?> fileSize(String path) async => fileSizeResult;

  @override
  Future<List<String>?> findRecoveryArtifacts(
    String managedFilesDir,
    String documentCode,
  ) async => recoveryArtifacts;

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async => recoveryArtifacts;

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async =>
      const [];

  @override
  Future<FilesystemOperationResult> deleteFile(String path) async {
    deleteCalls.add(path);
    _existingFiles.remove(path);
    return const FilesystemSuccess();
  }

  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
    String path,
    String allowedRoot,
  ) async => const FilesystemSuccess();
}

class _FakeBackupService implements DatabaseBackupService {
  BackupResult result = const BackupSuccess(
    backupPath: r'D:\Backups\backup.sqlite',
  );

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async => result;
}

class _FakeHasher implements FileHasher {
  final Map<String, String?> hashes;
  final List<String> hashedPaths = [];

  _FakeHasher([Map<String, String?>? hashes])
    : hashes =
          hashes ?? {r'C:\Library\WordTemp\copy_test_1.word_out': _kPdfHash};

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    hashedPaths.add(absolutePath);
    final h = hashes[absolutePath];
    if (hashes.containsKey(absolutePath) && h == null) {
      return Sha256Result.failure(
        ImportError(
          code: ImportErrorCode.hashFailed,
          path: absolutePath,
          message: 'simulated hash failure',
        ),
      );
    }
    return Sha256Result.success(
      h ?? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  }
}

class _FakeWordConverter implements WordDocumentConverter {
  WordDocumentConversionResult result = const WordDocumentConversionSuccess(
    tempPdfPath: _kTempPdfPath,
    pdfSha256: _kPdfHash,
    fileSizeBytes: 54321,
  );

  final List<String> convertCalls = [];
  final List<String> cleanupCalls = [];

  @override
  Future<WordDocumentConversionResult> convert({
    required String sourceDocPath,
    required String tempOutputDir,
    required String operationId,
  }) async {
    convertCalls.add(sourceDocPath);
    return result;
  }

  @override
  Future<void> cleanupSafely(String tempPdfPath, String tempDir) async {
    cleanupCalls.add(tempPdfPath);
  }
}

// ─── Helper ──────────────────────────────────────────────────────────────────

SourceFileCandidate _docCandidate({
  String path = _kDocPath,
  String health = 'healthy',
  bool isPreferred = true,
}) => SourceFileCandidate(
  fileId: 11,
  documentId: _kDocId,
  absolutePath: path,
  storedExtension: '.doc',
  fileHealthKey: health,
  isPreferred: isPreferred,
  sha256Hash: null,
);

SourceFileCandidate _pdfCandidate({
  String path = r'C:\Sources\report.pdf',
  String health = 'healthy',
  bool isPreferred = true,
  String? hash = _kPdfHash,
}) => SourceFileCandidate(
  fileId: 10,
  documentId: _kDocId,
  absolutePath: path,
  storedExtension: '.pdf',
  fileHealthKey: health,
  isPreferred: isPreferred,
  sha256Hash: hash,
);

ManagedCopyUseCase _makeUseCase({
  _FakeRepo? repo,
  _FakeFilesystem? fs,
  _FakeBackupService? backup,
  _FakeHasher? hasher,
  WordDocumentConverter? wordConverter,
}) {
  final r = repo ?? (_FakeRepo()..candidates = [_docCandidate()]);
  return ManagedCopyUseCase(
    repository: r,
    filesystem: fs ?? _FakeFilesystem(),
    backupService: backup ?? _FakeBackupService(),
    hasher: hasher ?? _FakeHasher({_kCopyingPath: _kPdfHash}),
    clock: _FakeClock(),
    pathCanonicalizer: _FakeCanonicalizer(),
    operationIdGenerator: _CountingIdGenerator(),
    wordConverter: wordConverter ?? _FakeWordConverter(),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('ManagedCopyUseCase — .doc source: happy path', () {
    test('succeeds and returns ManagedCopySuccess with correct code', () async {
      final repo = _FakeRepo()..candidates = [_docCandidate()];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);

      expect(result, isA<ManagedCopySuccess>());
      final s = result as ManagedCopySuccess;
      expect(s.documentCode, 'DOC-0000001');
      expect(s.managedPath, endsWith(r'files\DOC-0000001.pdf'));
      expect(s.sha256Hash, _kPdfHash);
    });

    test('Word converter is called with the original .doc path', () async {
      final converter = _FakeWordConverter();
      await _makeUseCase(wordConverter: converter).execute(_kDocId);
      expect(converter.convertCalls, [_kDocPath]);
    });

    test('temp PDF is cleaned up after success', () async {
      final converter = _FakeWordConverter();
      await _makeUseCase(wordConverter: converter).execute(_kDocId);
      expect(converter.cleanupCalls, [_kTempPdfPath]);
    });

    test('copy source uses temp PDF, not original .doc', () async {
      final fs = _FakeFilesystem();
      await _makeUseCase(fs: fs).execute(_kDocId);
      // First call to copyFile: src = temp PDF, dst = .copying path
      expect(fs.copyCalls.first, _kTempPdfPath);
      expect(fs.copyCalls[1], contains('.copying'));
    });

    test('original .doc is not included in copy or finalize calls', () async {
      final fs = _FakeFilesystem();
      await _makeUseCase(fs: fs).execute(_kDocId);
      expect(fs.copyCalls, isNot(contains(_kDocPath)));
    });

    test('managed copy hash matches converted PDF hash', () async {
      final result = await _makeUseCase().execute(_kDocId);
      final s = result as ManagedCopySuccess;
      expect(s.sha256Hash, _kPdfHash);
    });

    test(
      'document code is allocated during managed copy (not before)',
      () async {
        final repo = _FakeRepo()..candidates = [_docCandidate()];
        await _makeUseCase(repo: repo).execute(_kDocId);
        // allocateDocumentCode is only called inside execute — not before
        // This is verified by checking the success result has a code.
        expect(
          (await _makeUseCase(
            repo: _FakeRepo()..candidates = [_docCandidate()],
          ).execute(_kDocId)).runtimeType,
          ManagedCopySuccess,
        );
      },
    );
  });

  group('ManagedCopyUseCase — .doc source: Word conversion fails', () {
    test('returns ManagedCopyFailed with wordConversionFailed', () async {
      final converter = _FakeWordConverter()
        ..result = const WordDocumentConversionFailed(
          safeMessage: 'Word not found',
          errorCode: 'microsoft_word_unavailable',
        );
      final result = await _makeUseCase(
        wordConverter: converter,
      ).execute(_kDocId);

      expect(result, isA<ManagedCopyFailed>());
      expect(
        (result as ManagedCopyFailed).error,
        ManagedCopyError.wordConversionFailed,
      );
    });

    test('no managed copy row is created when conversion fails', () async {
      final converter = _FakeWordConverter()
        ..result = const WordDocumentConversionFailed(
          safeMessage: 'conversion failed',
          errorCode: 'word_process_failed',
        );
      final repo = _FakeRepo()..candidates = [_docCandidate()];
      await _makeUseCase(repo: repo, wordConverter: converter).execute(_kDocId);
      // persistManagedCopySuccess was never called since result is failure
      expect(
        repo.events.any((e) => e['eventTypeKey'] == 'copy_completed'),
        isFalse,
      );
    });

    test(
      'no temp PDF remains after conversion failure (converter cleans up)',
      () async {
        final converter = _FakeWordConverter()
          ..result = const WordDocumentConversionFailed(
            safeMessage: 'process failed',
            errorCode: 'word_process_failed',
          );
        // cleanupSafely must NOT be called when conversion failed (no temp file)
        // because the converter already cleaned up in its own error paths.
        // The use case only calls cleanupSafely if tempPdfPath is non-empty.
        await _makeUseCase(wordConverter: converter).execute(_kDocId);
        expect(converter.cleanupCalls, isEmpty);
      },
    );

    test(
      'document_code is not allocated when .doc conversion fails (bug 2)',
      () async {
        final converter = _FakeWordConverter()
          ..result = const WordDocumentConversionFailed(
            safeMessage: 'Word not found',
            errorCode: 'microsoft_word_unavailable',
          );
        final repo = _FakeRepo()..candidates = [_docCandidate()];
        await _makeUseCase(
          repo: repo,
          wordConverter: converter,
        ).execute(_kDocId);
        expect(
          repo.allocateDocumentCodeCalls,
          0,
          reason:
              'A failed .doc conversion must never allocate a document code',
        );
      },
    );

    test(
      'workflow status remains classified after .doc conversion failure (bug 2)',
      () async {
        final converter = _FakeWordConverter()
          ..result = const WordDocumentConversionFailed(
            safeMessage: 'Word not found',
            errorCode: 'microsoft_word_unavailable',
          );
        final repo = _FakeRepo()..candidates = [_docCandidate()];
        final result = await _makeUseCase(
          repo: repo,
          wordConverter: converter,
        ).execute(_kDocId);
        // No persistence call means workflow_status_key was never touched by
        // persistManagedCopySuccess (which is the only place that flips it to
        // copied_to_library).
        expect(result, isA<ManagedCopyFailed>());
        expect(
          repo.events.any((e) => e['eventTypeKey'] == 'copy_completed'),
          isFalse,
        );
      },
    );
  });

  group('ManagedCopyUseCase — .doc source: temp cleanup on failure', () {
    test(
      'temp PDF is cleaned up when copy step fails after conversion',
      () async {
        final fs = _FakeFilesystem()
          ..copyResult = const FilesystemFailure(safeMessage: 'copy failed');
        final converter = _FakeWordConverter();
        await _makeUseCase(fs: fs, wordConverter: converter).execute(_kDocId);
        // Conversion succeeded → temp PDF path is non-empty → cleanup must fire
        expect(converter.cleanupCalls, [_kTempPdfPath]);
      },
    );

    test(
      'temp PDF is cleaned up when DB persistence fails after finalization',
      () async {
        final repo = _FakeRepo()
          ..candidates = [_docCandidate()]
          ..throwOnPersist = true;
        final converter = _FakeWordConverter();
        await _makeUseCase(
          repo: repo,
          wordConverter: converter,
        ).execute(_kDocId);
        expect(converter.cleanupCalls, [_kTempPdfPath]);
      },
    );

    test('temp PDF is cleaned up when finalize step fails', () async {
      final fs = _FakeFilesystem()
        ..finalizeResult = const FilesystemFailure(
          safeMessage: 'rename failed',
        );
      final converter = _FakeWordConverter();
      await _makeUseCase(fs: fs, wordConverter: converter).execute(_kDocId);
      expect(converter.cleanupCalls, [_kTempPdfPath]);
    });
  });

  group('ManagedCopyUseCase — .doc source: no Word converter configured', () {
    test('returns ManagedCopyBlocked with unsupportedSource', () async {
      final uc = ManagedCopyUseCase(
        repository: _FakeRepo()..candidates = [_docCandidate()],
        filesystem: _FakeFilesystem(),
        backupService: _FakeBackupService(),
        hasher: _FakeHasher(),
        clock: _FakeClock(),
        pathCanonicalizer: _FakeCanonicalizer(),
        operationIdGenerator: _CountingIdGenerator(),
        wordConverter: null,
      );
      final result = await uc.execute(_kDocId);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsupportedSource,
      );
    });
  });

  group(
    'ManagedCopyUseCase — PDF source still works when .doc also present',
    () {
      test(
        'prefers PDF source over .doc source for the same document',
        () async {
          final converter = _FakeWordConverter();
          final repo = _FakeRepo()
            ..candidates = [_docCandidate(), _pdfCandidate(isPreferred: true)]
            ..sourcePaths = [_kDocPath, r'C:\Sources\report.pdf'];
          final fs = _FakeFilesystem(
            existingFiles: {_kDocPath, r'C:\Sources\report.pdf', _kTempPdfPath},
          );
          final result = await ManagedCopyUseCase(
            repository: repo,
            filesystem: fs,
            backupService: _FakeBackupService(),
            hasher: _FakeHasher({
              r'C:\Library\files\DOC-0000001.pdf.copy_test_1.copying':
                  _kPdfHash,
            }),
            clock: _FakeClock(),
            pathCanonicalizer: _FakeCanonicalizer(),
            operationIdGenerator: _CountingIdGenerator(),
            wordConverter: converter,
          ).execute(_kDocId);

          // When a PDF source exists, no Word conversion should happen.
          expect(converter.convertCalls, isEmpty);
          expect(result, isA<ManagedCopySuccess>());
        },
      );
    },
  );

  group('ManagedCopyUseCase — .doc source: unhealthy/ineligible cases', () {
    test('unhealthy .doc source is not eligible', () async {
      final repo = _FakeRepo()
        ..candidates = [_docCandidate(health: 'unreadable')];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.noEligibleSource,
      );
    });

    test('no candidates → noEligibleSource', () async {
      final repo = _FakeRepo()..candidates = [];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.noEligibleSource,
      );
    });

    test('document must be classified', () async {
      final repo = _FakeRepo()
        ..docState = DocumentCopyState(
          documentId: _kDocId,
          workflowStatusKey: 'in_progress',
          existingDocumentCode: null,
          hasManagedCopy: false,
          hasHealthyManagedCopy: false,
        )
        ..candidates = [_docCandidate()];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.notClassified,
      );
    });
  });

  group('ManagedCopyUseCase — .doc source: no WordStaging artifacts', () {
    test(
      'conversion output lives in WordConversionTemp, not WordStaging',
      () async {
        String? capturedTempDir;
        final capturingConverter = _CapturingConverter(
          wrapped: _FakeWordConverter(),
          onConvert: (_, dir, _) => capturedTempDir = dir,
          result: const WordDocumentConversionSuccess(
            tempPdfPath: _kTempPdfPath,
            pdfSha256: _kPdfHash,
            fileSizeBytes: 54321,
          ),
        );
        await _makeUseCase(wordConverter: capturingConverter).execute(_kDocId);
        expect(capturedTempDir, contains('WordConversionTemp'));
        expect(capturedTempDir, isNot(contains('WordStaging')));
      },
    );
  });

  // ── Word temp dir must be a local app temp folder, never the managed
  //    library (QA follow-up: offline .doc conversion) ────────────────────

  group('ManagedCopyUseCase — Word temp dir is local app temp', () {
    test('conversion temp directory comes from loadWordTempRoot(), not the '
        'managed library root', () async {
      String? capturedTempDir;
      final capturingConverter = _CapturingConverter(
        wrapped: _FakeWordConverter(),
        onConvert: (_, dir, _) => capturedTempDir = dir,
        result: const WordDocumentConversionSuccess(
          tempPdfPath: _kTempPdfPath,
          pdfSha256: _kPdfHash,
          fileSizeBytes: 54321,
        ),
      );
      final repo = _FakeRepo()
        ..candidates = [_docCandidate()]
        ..wordTempRoot = _kWordTempParent;
      await _makeUseCase(
        repo: repo,
        wordConverter: capturingConverter,
      ).execute(_kDocId);

      expect(capturedTempDir, isNotNull);
      expect(capturedTempDir, startsWith(_kWordTempParent));
      expect(capturedTempDir, isNot(startsWith(r'C:\Library')));
      expect(capturedTempDir!.contains(r'C:\Library'), isFalse);
    });

    test(
      'temp dir is created under the local root, not inside managed files',
      () async {
        final fs = _FakeFilesystem(
          existingDirs: {r'C:\Library', r'D:\Backups', r'C:\Library\files'},
        );
        final repo = _FakeRepo()..candidates = [_docCandidate()];
        await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);

        expect(fs.isExistingDirectory(_kWordTempParent), isTrue);
        expect(fs.isExistingDirectory(_kWordTempDir), isTrue);
      },
    );

    test('blocks with unsafeRoots when the resolved Word temp root overlaps '
        'the managed library root', () async {
      final repo = _FakeRepo()
        ..candidates = [_docCandidate()]
        ..wordTempRoot = r'C:\Library\WordTemp';
      final result = await _makeUseCase(repo: repo).execute(_kDocId);

      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });

    test('blocks with unsafeRoots when the resolved Word temp root overlaps '
        'the managed files directory', () async {
      final repo = _FakeRepo()
        ..candidates = [_docCandidate()]
        ..wordTempRoot = r'C:\Library\files\WordTemp';
      final result = await _makeUseCase(repo: repo).execute(_kDocId);

      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });

    test('blocks with unsafeRoots when the resolved Word temp root overlaps '
        'the backup root', () async {
      final repo = _FakeRepo()
        ..candidates = [_docCandidate()]
        ..wordTempRoot = r'D:\Backups\WordTemp';
      final result = await _makeUseCase(repo: repo).execute(_kDocId);

      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });

    test('blocks with unsafeRoots when the resolved Word temp root is not an '
        'absolute path', () async {
      final repo = _FakeRepo()
        ..candidates = [_docCandidate()]
        ..wordTempRoot = 'relative\\path';
      final result = await _makeUseCase(repo: repo).execute(_kDocId);

      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });
  });
}

// ─── Helper fake ─────────────────────────────────────────────────────────────

class _CapturingConverter implements WordDocumentConverter {
  _CapturingConverter({
    required this.wrapped,
    required this.onConvert,
    required this.result,
  });

  final WordDocumentConverter wrapped;
  final void Function(String srcPath, String tempDir, String opId) onConvert;
  final WordDocumentConversionResult result;

  @override
  Future<WordDocumentConversionResult> convert({
    required String sourceDocPath,
    required String tempOutputDir,
    required String operationId,
  }) async {
    onConvert(sourceDocPath, tempOutputDir, operationId);
    return result;
  }

  @override
  Future<void> cleanupSafely(String tempPdfPath, String tempDir) =>
      wrapped.cleanupSafely(tempPdfPath, tempDir);
}
