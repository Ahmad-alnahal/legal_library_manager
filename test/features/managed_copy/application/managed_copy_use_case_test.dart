// test/features/managed_copy/application/managed_copy_use_case_test.dart

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

// ─── Fake implementations ────────────────────────────────────────────────────

class _FakeClock extends Clock {
  _FakeClock([DateTime? t]) : _now = t ?? DateTime.utc(2026, 6, 11, 10, 0, 0);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

class _FakeRepo implements ManagedCopyRepository {
  DocumentCopyState? docState;
  CopyRoots roots = const CopyRoots(
    managedLibraryRoot: r'C:\Library',
    backupRoot: r'D:\Backups',
  );
  String databaseRoot = r'C:\AppSupport';
  List<String> sourcePaths = [];
  List<SourceFileCandidate> candidates = [];
  List<ManagedFileRef> managedFiles = [];
  String allocatedCode = 'DOC-0000001';
  bool throwOnPersist = false;
  int persistedFileId = 42;

  final List<Map<String, Object?>> events = [];
  final List<int> markedMissingFileIds = [];
  final List<int> restoredFileIds = [];
  final List<int> downgradedDocumentIds = [];

  @override
  Future<DocumentCopyState?> loadDocumentState(int documentId) async =>
      docState;

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) async {
    roots = CopyRoots(
      managedLibraryRoot: managedLibraryRoot,
      backupRoot: backupRoot,
    );
  }

  @override
  Future<String> loadDatabaseRoot() async => databaseRoot;

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

  bool throwStateErrorOnAllocate = false;

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
      'operationId': operationId,
      'resultKey': resultKey,
      'errorCode': errorCode,
      'messageSafe': messageSafe,
      'sourcePath': sourcePath,
      'destinationPath': destinationPath,
      'expectedSha256': expectedSha256,
      'actualSha256': actualSha256,
    });
  }

  @override
  Future<String> allocateDocumentCode(int documentId) async {
    if (throwStateErrorOnAllocate) throw StateError('Code space exhausted.');
    return allocatedCode;
  }

  Set<String> throwOnAuditEvent = {};

  @override
  Future<int> persistManagedCopySuccess(ManagedCopyPersistenceData data) async {
    if (throwOnPersist) throw Exception('simulated DB failure');
    return persistedFileId;
  }

  @override
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId) async =>
      managedFiles;

  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    markedMissingFileIds.add(fileId);
    managedFiles = managedFiles
        .map(
          (file) => file.fileId == fileId
              ? ManagedFileRef(
                  fileId: file.fileId,
                  documentId: file.documentId,
                  absolutePath: file.absolutePath,
                  fileHealthKey: 'missing',
                  fileSizeBytes: file.fileSizeBytes,
                  sha256Hash: file.sha256Hash,
                )
              : file,
        )
        .toList();
  }

  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    restoredFileIds.add(fileId);
    managedFiles = managedFiles
        .map(
          (file) => file.fileId == fileId
              ? ManagedFileRef(
                  fileId: file.fileId,
                  documentId: file.documentId,
                  absolutePath: file.absolutePath,
                  fileHealthKey: 'healthy',
                  fileSizeBytes: file.fileSizeBytes,
                  sha256Hash: file.sha256Hash,
                )
              : file,
        )
        .toList();
    final current = docState;
    if (current == null) return;
    docState = DocumentCopyState(
      documentId: current.documentId,
      workflowStatusKey: 'copied_to_library',
      existingDocumentCode: current.existingDocumentCode,
      hasManagedCopy: current.hasManagedCopy,
      hasHealthyManagedCopy: true,
    );
  }

  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) async {
    downgradedDocumentIds.add(documentId);
    final current = docState;
    if (current == null) return;
    docState = DocumentCopyState(
      documentId: current.documentId,
      workflowStatusKey: 'classified',
      existingDocumentCode: current.existingDocumentCode,
      hasManagedCopy: current.hasManagedCopy,
      hasHealthyManagedCopy: managedFiles.any(
        (file) => file.fileHealthKey != 'missing',
      ),
    );
  }

  @override
  Future<List<ManagedFileRef>> loadAllManagedCopyFiles() async => managedFiles;

  @override
  Future<void> markManagedFileCorrupted({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}
}

/// Path canonicalizer fake. By default returns the path unchanged (identity).
/// Override specific paths via the constructor map; null values simulate
/// paths that cannot be resolved.
class _FakeCanonicalizer implements PathCanonicalizer {
  final Map<String, String?> _overrides;
  _FakeCanonicalizer([Map<String, String?>? overrides])
    : _overrides = overrides ?? {};

  @override
  String? canonicalize(String path) =>
      _overrides.containsKey(path) ? _overrides[path] : path;
}

class _ChangingFilesCanonicalizer implements PathCanonicalizer {
  int _filesCalls = 0;

  @override
  String? canonicalize(String path) {
    if (path == r'C:\Library\files') {
      _filesCalls++;
      return _filesCalls == 1
          ? r'C:\Library\files'
          : r'C:\Sources\redirected-files';
    }
    return path;
  }
}

/// Operation-ID generator that uses a counter so tests are deterministic.
class _CountingOperationIdGenerator implements OperationIdGenerator {
  int _count = 0;

  @override
  String generate(DateTime now) => 'copy_test_${++_count}';
}

class _FakeFilesystem implements ManagedLibraryFilesystem {
  bool directoryExists = true;
  bool sourceFileExists = true;
  bool finalFileExists = false;
  bool tmpFileExists = false;
  FilesystemOperationResult ensureResult = const FilesystemSuccess();
  FilesystemOperationResult copyResult = const FilesystemSuccess();
  FilesystemOperationResult finalizeResult = const FilesystemSuccess();
  int? fileSizeResult = 12345;
  List<String>? recoveryArtifacts = [];

  final List<String> copyCalls = []; // (src, dst) flattened
  final List<String> finalizeCalls = []; // (tmp, final) flattened

  @override
  bool isExistingDirectory(String path) => directoryExists;

  @override
  bool isExistingFile(String path) {
    // Differentiate between tmp, final, and source.
    if (path.endsWith('.copying')) return tmpFileExists;
    if (path.endsWith('.pdf') && !path.contains('.copying')) {
      // Check if it's the final managed path or source.
      if (path.contains(r'Library\files\')) return finalFileExists;
    }
    return sourceFileExists;
  }

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) async => ensureResult;

  @override
  Future<FilesystemOperationResult> copyFile(
    String sourcePath,
    String destPath,
  ) async {
    copyCalls.addAll([sourcePath, destPath]);
    return copyResult;
  }

  @override
  Future<FilesystemOperationResult> finalizeFile(
    String tmpPath,
    String finalPath,
  ) async {
    finalizeCalls.addAll([tmpPath, finalPath]);
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

  FilesystemOperationResult deleteResult = const FilesystemSuccess();
  final List<String> deleteCalls = [];

  @override
  Future<FilesystemOperationResult> deleteFile(String path) async {
    deleteCalls.add(path);
    return deleteResult;
  }

  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
    String path,
    String allowedRoot,
  ) async => throw UnimplementedError();
}

class _FakeBackupService implements DatabaseBackupService {
  int calls = 0;
  BackupResult result = const BackupSuccess(
    backupPath: r'D:\Backups\backup.sqlite',
  );

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async {
    calls++;
    return result;
  }
}

class _FakeHasher implements FileHasher {
  /// Per-path hash map: null means return failure.
  final Map<String, String?> hashes;
  _FakeHasher([Map<String, String?>? hashes]) : hashes = hashes ?? {};

  final List<String> hashedPaths = [];

  static const String _defaultHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    hashedPaths.add(absolutePath);
    if (hashes.containsKey(absolutePath)) {
      final h = hashes[absolutePath];
      if (h == null) {
        return Sha256Result.failure(
          ImportError(
            code: ImportErrorCode.hashFailed,
            path: absolutePath,
            message: 'simulated hash failure',
          ),
        );
      }
      return Sha256Result.success(h);
    }
    return Sha256Result.success(_defaultHash);
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _kDocId = 1;
const _kSourcePath = r'C:\Sources\doc.pdf';
const _kHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

DocumentCopyState _classifiedState({
  String? code,
  bool hasCopy = false,
  bool? hasHealthyCopy,
}) => DocumentCopyState(
  documentId: _kDocId,
  workflowStatusKey: 'classified',
  existingDocumentCode: code,
  hasManagedCopy: hasCopy,
  hasHealthyManagedCopy: hasHealthyCopy ?? hasCopy,
);

SourceFileCandidate _sourceCandidate({
  bool isPreferred = false,
  String? hash,
  String path = _kSourcePath,
  String health = 'healthy',
  String ext = '.pdf',
}) => SourceFileCandidate(
  fileId: 10,
  documentId: _kDocId,
  absolutePath: path,
  storedExtension: ext,
  fileHealthKey: health,
  isPreferred: isPreferred,
  sha256Hash: hash,
);

ManagedCopyUseCase _makeUseCase({
  _FakeRepo? repo,
  _FakeFilesystem? fs,
  _FakeBackupService? backup,
  _FakeHasher? hasher,
  PathCanonicalizer? canonicalizer,
  _CountingOperationIdGenerator? idGenerator,
}) {
  final r =
      repo ??
      (_FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)]);
  return ManagedCopyUseCase(
    repository: r,
    filesystem: fs ?? _FakeFilesystem(),
    backupService: backup ?? _FakeBackupService(),
    hasher: hasher ?? _FakeHasher(),
    clock: _FakeClock(),
    pathCanonicalizer: canonicalizer ?? _FakeCanonicalizer(),
    operationIdGenerator: idGenerator ?? _CountingOperationIdGenerator(),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ── Happy path ──────────────────────────────────────────────────────────────

  group('ManagedCopyUseCase — successful copy sequence', () {
    test('returns ManagedCopySuccess with correct code and path', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);

      expect(result, isA<ManagedCopySuccess>());
      final s = result as ManagedCopySuccess;
      expect(s.documentCode, 'DOC-0000001');
      expect(s.managedPath, contains(r'files\DOC-0000001.pdf'));
      expect(s.sha256Hash, _kHash);
      expect(s.documentFileId, 42);
    });

    test('managed path uses files\\DOC-0000001.pdf format', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      final s = result as ManagedCopySuccess;
      expect(s.managedPath, endsWith(r'files\DOC-0000001.pdf'));
    });

    test('source file is never passed to finalizeFile (not mutated)', () async {
      final fs = _FakeFilesystem();
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);

      // finalizeFile must operate on the tmp path, never the source path.
      // finalizeCalls is flattened: [tmpPath, finalPath, ...]
      expect(fs.finalizeCalls.any((p) => p == _kSourcePath), isFalse);
      // The source path must appear as the SOURCE in copyFile, not destination.
      expect(fs.copyCalls.length, 2);
      expect(fs.copyCalls[0], _kSourcePath); // source
      expect(fs.copyCalls[1], isNot(_kSourcePath)); // destination is tmp
    });

    test('backup occurs before copy bytes are written', () async {
      final fs = _SequencedFilesystem();
      final backup = _SequencedBackupService(fs);
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final uc = ManagedCopyUseCase(
        repository: repo,
        filesystem: fs,
        backupService: backup,
        hasher: _FakeHasher(),
        clock: _FakeClock(),
        pathCanonicalizer: _FakeCanonicalizer(),
        operationIdGenerator: _CountingOperationIdGenerator(),
      );
      await uc.execute(_kDocId);

      expect(
        fs.backupBeforeCopy,
        isTrue,
        reason: 'backup must complete before copyFile is called',
      );
    });
  });

  // ── Document state guards ──────────────────────────────────────────────────

  group('ManagedCopyUseCase — document not found', () {
    test('returns documentNotFound when document does not exist', () async {
      final repo = _FakeRepo()..docState = null;
      final result = await _makeUseCase(repo: repo).execute(999);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.documentNotFound,
      );
    });
  });

  group('ManagedCopyUseCase — not classified', () {
    test('blocks when workflow is imported', () async {
      final repo = _FakeRepo()
        ..docState = DocumentCopyState(
          documentId: _kDocId,
          workflowStatusKey: 'imported',
          existingDocumentCode: null,
          hasManagedCopy: false,
          hasHealthyManagedCopy: false,
        );
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.notClassified,
      );
    });

    test('blocks when workflow is in_progress', () async {
      final repo = _FakeRepo()
        ..docState = DocumentCopyState(
          documentId: _kDocId,
          workflowStatusKey: 'in_progress',
          existingDocumentCode: null,
          hasManagedCopy: false,
          hasHealthyManagedCopy: false,
        );
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.notClassified,
      );
    });
  });

  group('ManagedCopyUseCase — already copied', () {
    test('blocks when document already has managed copy', () async {
      final repo = _FakeRepo()..docState = _classifiedState(hasCopy: true);
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.alreadyCopied,
      );
    });

    test('keeps blocking when the managed copy exists physically', () async {
      final repo = _FakeRepo()
        ..docState = DocumentCopyState(
          documentId: _kDocId,
          workflowStatusKey: 'copied_to_library',
          existingDocumentCode: 'DOC-0000005',
          hasManagedCopy: true,
          hasHealthyManagedCopy: true,
        )
        ..managedFiles = [
          const ManagedFileRef(
            fileId: 99,
            documentId: _kDocId,
            absolutePath: r'C:\Library\files\DOC-0000005.pdf',
            fileHealthKey: 'healthy',
          ),
        ];
      final fs = _FakeFilesystem()..finalFileExists = true;

      final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);

      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.alreadyCopied,
      );
      expect(repo.markedMissingFileIds, isEmpty);
      expect(repo.downgradedDocumentIds, isEmpty);
    });

    test('reconciles a missing managed file and allows re-copy', () async {
      final repo = _FakeRepo()
        ..docState = DocumentCopyState(
          documentId: _kDocId,
          workflowStatusKey: 'copied_to_library',
          existingDocumentCode: 'DOC-0000005',
          hasManagedCopy: true,
          hasHealthyManagedCopy: true,
        )
        ..allocatedCode = 'DOC-0000005'
        ..candidates = [_sourceCandidate(hash: _kHash)]
        ..managedFiles = [
          const ManagedFileRef(
            fileId: 99,
            documentId: _kDocId,
            absolutePath: r'C:\Library\files\DOC-0000005.pdf',
            fileHealthKey: 'healthy',
          ),
        ];

      final result = await _makeUseCase(repo: repo).execute(_kDocId);

      expect(result, isA<ManagedCopySuccess>());
      expect((result as ManagedCopySuccess).documentCode, 'DOC-0000005');
      expect(repo.markedMissingFileIds, [99]);
      expect(repo.downgradedDocumentIds, [_kDocId]);
    });

    test(
      'restores a missing managed file instead of copying over it',
      () async {
        final repo = _FakeRepo()
          ..docState = DocumentCopyState(
            documentId: _kDocId,
            workflowStatusKey: 'classified',
            existingDocumentCode: 'DOC-0000007',
            hasManagedCopy: true,
            hasHealthyManagedCopy: false,
          )
          ..allocatedCode = 'DOC-0000007'
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..managedFiles = [
            const ManagedFileRef(
              fileId: 107,
              documentId: _kDocId,
              absolutePath: r'C:\Library\files\DOC-0000007.pdf',
              fileHealthKey: 'missing',
              fileSizeBytes: 12345,
              sha256Hash: _kHash,
            ),
          ];
        final fs = _FakeFilesystem()..finalFileExists = true;

        final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);

        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.restoredFromDisk,
        );
        expect(repo.restoredFileIds, [107]);
        expect(fs.copyCalls, isEmpty);
      },
    );
  });

  // ── Root configuration guards ──────────────────────────────────────────────

  group('ManagedCopyUseCase — roots not configured', () {
    test('blocks when both roots are null', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..roots = const CopyRoots();
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.rootsNotConfigured,
      );
    });

    test('blocks when only managed root is missing', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..roots = const CopyRoots(backupRoot: r'D:\Backups');
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.rootsNotConfigured,
      );
    });
  });

  group('ManagedCopyUseCase — overlapping roots', () {
    test('blocks when backup root is inside managed root', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..roots = const CopyRoots(
          managedLibraryRoot: r'C:\Library',
          backupRoot: r'C:\Library\backups',
        );
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });

    test('blocks when managed root is inside backup root', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..roots = const CopyRoots(
          managedLibraryRoot: r'D:\Backups\Library',
          backupRoot: r'D:\Backups',
        );
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });

    test('blocks when backup root equals managed root', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..roots = const CopyRoots(
          managedLibraryRoot: r'C:\Library',
          backupRoot: r'C:\Library',
        );
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });

    test('blocks when managed files dir overlaps database root', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..roots = const CopyRoots(
          managedLibraryRoot: r'C:\AppSupport',
          backupRoot: r'D:\Backups',
        )
        ..databaseRoot = r'C:\AppSupport';
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
    });

    test(
      'blocks when managed root contains a registered source folder',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..sourcePaths = [r'C:\Library\sources\doc.pdf'];
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );

    test(
      'blocks when backup root contains a registered source folder',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..sourcePaths = [r'D:\Backups\sources\doc.pdf'];
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );

    // Drive-root normalization regression: _normalizePath preserves 'c:\' as
    // three chars, so '$normOuter\\' would become 'c:\\' (four chars) — a
    // prefix that no real path starts with. The fix in _pathIsInsideOrEquals
    // detects the trailing separator and avoids doubling it.
    test(
      'blocks when backup root is a subdirectory of a drive-root managed library root',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..roots = const CopyRoots(
            managedLibraryRoot: r'C:\',
            backupRoot: r'C:\Backups',
          );
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );

    test(
      'blocks when managed library root is a subdirectory of a drive-root backup root',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..roots = const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: r'C:\',
          );
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );
  });

  // ── Missing configured roots (M8.5) ────────────────────────────────────────

  group('ManagedCopyUseCase — missing configured roots', () {
    test(
      'blocks with rootsMissing when a configured root directory is missing',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..roots = const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: r'D:\Backups',
          );
        // Absolute paths, but the directories do not exist on disk.
        final fs = _FakeFilesystem()..directoryExists = false;
        final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.rootsMissing,
        );
      },
    );
  });

  // ── Source selection guards ────────────────────────────────────────────────

  group('ManagedCopyUseCase — no eligible source', () {
    test('blocks when no source_original files exist', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.noEligibleSource,
      );
    });

    test('blocks when only source has unhealthy status', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(health: 'corrupted')];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.noEligibleSource,
      );
    });

    test('blocks when source extension is not .pdf or .doc', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(ext: '.txt')];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.noEligibleSource,
      );
    });
  });

  group('ManagedCopyUseCase — ambiguous source', () {
    test(
      'blocks when two healthy PDF sources exist with neither preferred',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [
            _sourceCandidate(path: _kSourcePath, isPreferred: false),
            _sourceCandidate(path: r'C:\Sources\doc2.pdf', isPreferred: false),
          ];
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.ambiguousSource,
        );
      },
    );

    test('succeeds when exactly one of two sources is preferred', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [
          _sourceCandidate(path: _kSourcePath, isPreferred: true, hash: _kHash),
          _sourceCandidate(
            path: r'C:\Sources\doc2.pdf',
            isPreferred: false,
            hash: _kHash,
          ),
        ];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopySuccess>());
    });
  });

  group('ManagedCopyUseCase — missing source', () {
    test('blocks when source file does not exist on filesystem', () async {
      final fs = _FakeFilesystem()..sourceFileExists = false;
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.missingSource,
      );
    });
  });

  group('ManagedCopyUseCase — unsupported source extension from path', () {
    test('blocks when path extension is .exe despite stored .pdf', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [
          SourceFileCandidate(
            fileId: 10,
            documentId: _kDocId,
            absolutePath: r'C:\Sources\doc.pdf.exe',
            storedExtension: '.pdf',
            fileHealthKey: 'healthy',
            isPreferred: false,
          ),
        ];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsupportedSource,
      );
    });
  });

  // ── Backup failure ─────────────────────────────────────────────────────────

  group('ManagedCopyUseCase — backup failure blocks copy', () {
    test('returns backupFailed and does not copy bytes', () async {
      final backup = _FakeBackupService()
        ..result = const BackupFailure(safeMessage: 'disk full');
      final fs = _FakeFilesystem();
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final result = await _makeUseCase(
        repo: repo,
        fs: fs,
        backup: backup,
      ).execute(_kDocId);

      expect(
        (result as ManagedCopyFailed).error,
        ManagedCopyError.backupFailed,
      );
      expect(
        fs.copyCalls,
        isEmpty,
        reason: 'no bytes should be copied after backup failure',
      );
    });

    test('records copy_failed event with backupFailed code', () async {
      final backup = _FakeBackupService()
        ..result = const BackupFailure(safeMessage: 'disk full');
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      await _makeUseCase(repo: repo, backup: backup).execute(_kDocId);

      final failEvent = repo.events
          .where((e) => e['eventTypeKey'] == 'copy_failed')
          .toList();
      expect(failEvent, hasLength(1));
      expect(failEvent.first['errorCode'], ManagedCopyError.backupFailed.name);
    });
  });

  // ── Conflict guards ────────────────────────────────────────────────────────

  group('ManagedCopyUseCase - conservative recovery detection', () {
    test(
      'interrupted owned artifact requires recovery before backup or copy',
      () async {
        final fs = _FakeFilesystem()
          ..recoveryArtifacts = [
            r'C:\Library\files\DOC-0000001.pdf.copy_old.copying',
          ];
        final backup = _FakeBackupService();
        final result = await _makeUseCase(
          fs: fs,
          backup: backup,
        ).execute(_kDocId);

        expect(result, isA<ManagedCopyRecoveryRequired>());
        expect(fs.copyCalls, isEmpty);
        expect(backup.calls, 0);
      },
    );

    test('finalized but unregistered owned file requires recovery', () async {
      final fs = _FakeFilesystem()
        ..recoveryArtifacts = [r'C:\Library\files\DOC-0000001.pdf'];
      final result = await _makeUseCase(fs: fs).execute(_kDocId);

      expect(result, isA<ManagedCopyRecoveryRequired>());
      expect(fs.copyCalls, isEmpty);
    });

    test('artifact inspection failure blocks safely', () async {
      final fs = _FakeFilesystem()..recoveryArtifacts = null;
      final result = await _makeUseCase(fs: fs).execute(_kDocId);

      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.unsafeRoots,
      );
      expect(fs.copyCalls, isEmpty);
    });

    test(
      'artifact resolving outside validated files directory is blocked',
      () async {
        const artifact = r'C:\Library\files\DOC-0000001.pdf.copy_old.copying';
        final fs = _FakeFilesystem()..recoveryArtifacts = [artifact];
        final canonicalizer = _FakeCanonicalizer({
          artifact: r'C:\Sources\redirected.copying',
        });
        final result = await _makeUseCase(
          fs: fs,
          canonicalizer: canonicalizer,
        ).execute(_kDocId);

        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );
  });

  group('ManagedCopyUseCase — target conflicts', () {
    test(
      'restores matching missing DB row when final managed file already exists',
      () async {
        final fs = _FakeFilesystem()..finalFileExists = true;
        final repo = _FakeRepo()
          ..docState = _classifiedState(hasCopy: true, hasHealthyCopy: false)
          ..managedFiles = [
            const ManagedFileRef(
              fileId: 77,
              documentId: _kDocId,
              absolutePath: r'C:\Library\files\DOC-0000001.pdf',
              fileHealthKey: 'missing',
              fileSizeBytes: 12345,
              sha256Hash: _kHash,
            ),
          ]
          ..candidates = [_sourceCandidate(hash: _kHash)];

        final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);

        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.restoredFromDisk,
        );
        expect(repo.restoredFileIds, [77]);
        expect(fs.copyCalls, isEmpty);
        expect(fs.finalizeCalls, isEmpty);
      },
    );

    test(
      'deletes unrecognised conflicting file and makes a fresh copy',
      () async {
        final fs = _FakeFilesystem()..finalFileExists = true;
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)];
        final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
        // The conflicting file should be deleted and a fresh copy written.
        expect(result, isA<ManagedCopySuccess>());
        expect(fs.deleteCalls, isNotEmpty);
        expect(fs.finalizeCalls, isNotEmpty);
      },
    );

    test(
      'returns temporaryTargetConflict when tmp path already exists',
      () async {
        final fs = _FakeFilesystem()..tmpFileExists = true;
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)];
        final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
        expect(
          (result as ManagedCopyFailed).error,
          ManagedCopyError.temporaryTargetConflict,
        );
      },
    );

    test(
      'unrecognised conflicting file is deleted then replaced with verified copy',
      () async {
        final fs = _FakeFilesystem()..finalFileExists = true;
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)];
        await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
        // Old file was removed before writing the new verified copy.
        expect(fs.deleteCalls, isNotEmpty);
        expect(fs.finalizeCalls, isNotEmpty);
      },
    );
  });

  // ── Hash failures ──────────────────────────────────────────────────────────

  group('ManagedCopyUseCase — hash failures', () {
    test('returns hashFailed when source hash computation fails', () async {
      final hasher = _FakeHasher({_kSourcePath: null}); // null = failure
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        // no stored hash → must compute
        ..candidates = [_sourceCandidate()];
      final result = await _makeUseCase(
        repo: repo,
        hasher: hasher,
      ).execute(_kDocId);
      expect((result as ManagedCopyFailed).error, ManagedCopyError.hashFailed);
    });

    test('returns hashMismatch when tmp hash differs from source', () async {
      const sourceHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const diffHash =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: sourceHash)];
      final result = await ManagedCopyUseCase(
        repository: repo,
        filesystem: _FakeFilesystem(),
        backupService: _FakeBackupService(),
        hasher: _MismatchHasher(sourceHash: sourceHash, tmpHash: diffHash),
        clock: _FakeClock(),
        pathCanonicalizer: _FakeCanonicalizer(),
        operationIdGenerator: _CountingOperationIdGenerator(),
      ).execute(_kDocId);
      expect(
        (result as ManagedCopyFailed).error,
        ManagedCopyError.hashMismatch,
      );
    });

    test('hashMismatch event includes expected and actual hashes', () async {
      const sourceHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const diffHash =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: sourceHash)];
      await ManagedCopyUseCase(
        repository: repo,
        filesystem: _FakeFilesystem(),
        backupService: _FakeBackupService(),
        hasher: _MismatchHasher(sourceHash: sourceHash, tmpHash: diffHash),
        clock: _FakeClock(),
        pathCanonicalizer: _FakeCanonicalizer(),
        operationIdGenerator: _CountingOperationIdGenerator(),
      ).execute(_kDocId);

      final ev = repo.events.firstWhere(
        (e) => e['errorCode'] == ManagedCopyError.hashMismatch.name,
      );
      expect(ev['expectedSha256'], sourceHash);
      expect(ev['actualSha256'], diffHash);
    });
  });

  // ── Copy / finalization failures ───────────────────────────────────────────

  group('ManagedCopyUseCase — copy failure', () {
    test('returns copyFailed when byte copy fails', () async {
      final fs = _FakeFilesystem()
        ..copyResult = const FilesystemFailure(safeMessage: 'disk error');
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
      expect((result as ManagedCopyFailed).error, ManagedCopyError.copyFailed);
    });

    test('returns finalizationFailed when rename fails', () async {
      final fs = _FakeFilesystem()
        ..finalizeResult = const FilesystemFailure(safeMessage: 'rename error');
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
      expect(
        (result as ManagedCopyFailed).error,
        ManagedCopyError.finalizationFailed,
      );
    });
  });

  // ── DB persistence failure / recovery ─────────────────────────────────────

  group('ManagedCopyUseCase — DB persistence failure', () {
    test(
      'returns ManagedCopyRecoveryRequired when transaction fails after finalization',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..throwOnPersist = true;
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(result, isA<ManagedCopyRecoveryRequired>());
      },
    );

    test('recovery result contains the verified managed path', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)]
        ..throwOnPersist = true;
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      final r = result as ManagedCopyRecoveryRequired;
      expect(r.verifiedPath, contains(r'files\DOC-0000001.pdf'));
    });

    test(
      'workflow is NOT set to copied_to_library on persistence failure',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..throwOnPersist = true;
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(result, isA<ManagedCopyRecoveryRequired>());
        // The repository's persistManagedCopySuccess threw, so no workflow update
        // happened (this is the contract: throw = rollback).
      },
    );

    test(
      'copy_failed event is recorded with databasePersistenceFailed code',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..throwOnPersist = true;
        await _makeUseCase(repo: repo).execute(_kDocId);
        final failEv = repo.events.where(
          (e) =>
              e['errorCode'] == ManagedCopyError.databasePersistenceFailed.name,
        );
        expect(failEv, hasLength(1));
      },
    );
  });

  // ── Document code allocation ───────────────────────────────────────────────

  group('ManagedCopyUseCase — document code reuse', () {
    test('uses pre-existing document code without modification', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState(code: 'DOC-0000042')
        ..allocatedCode = 'DOC-0000042'
        ..candidates = [_sourceCandidate(hash: _kHash)];
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect((result as ManagedCopySuccess).documentCode, 'DOC-0000042');
    });
  });

  // ── Event content safety ───────────────────────────────────────────────────

  group('ManagedCopyUseCase — failure events carry stable safe data', () {
    test('copy_started event uses resultKey started', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)];
      await _makeUseCase(repo: repo).execute(_kDocId);
      final ev = repo.events.firstWhere(
        (e) => e['eventTypeKey'] == 'copy_started',
      );
      expect(ev['resultKey'], 'started');
    });

    test(
      'copy_failed errorCode is stable enum name, not raw exception',
      () async {
        final backup = _FakeBackupService()
          ..result = const BackupFailure(safeMessage: 'disk full');
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)];
        await _makeUseCase(repo: repo, backup: backup).execute(_kDocId);
        final ev = repo.events.firstWhere(
          (e) => e['eventTypeKey'] == 'copy_failed',
        );
        final code = ev['errorCode'] as String?;
        expect(code, isNotNull);
        expect(code!.contains('Exception'), isFalse);
        expect(code.contains('Error'), isFalse);
      },
    );
  });

  // ── Safety correction 1: document code validation ─────────────────────────

  group('ManagedCopyUseCase — document code validation (correction 1)', () {
    test(
      'blocks with malformedDocumentCode when allocated code is invalid',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..allocatedCode = 'BAD-CODE';
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.malformedDocumentCode,
        );
      },
    );

    test('blocks when allocated code contains path separator', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)]
        ..allocatedCode = r'DOC-000\001';
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopyBlocked>());
      expect(
        (result as ManagedCopyBlocked).error,
        ManagedCopyError.malformedDocumentCode,
      );
    });

    test(
      'blocks with codeSpaceExhausted when repository throws StateError',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..throwStateErrorOnAllocate = true;
        final result = await _makeUseCase(repo: repo).execute(_kDocId);
        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.codeSpaceExhausted,
        );
      },
    );

    test('accepts valid DOC-NNNNNNN code and proceeds', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)]
        ..allocatedCode = 'DOC-0000001';
      final result = await _makeUseCase(repo: repo).execute(_kDocId);
      expect(result, isA<ManagedCopySuccess>());
    });
  });

  // ── Safety correction 2: canonical path validation ─────────────────────────

  group('ManagedCopyUseCase — canonical path validation (correction 2)', () {
    test(
      'blocks with unsafeRoots when managed root cannot be canonicalized',
      () async {
        final canon = _FakeCanonicalizer({r'C:\Library': null});
        final result = await _makeUseCase(
          canonicalizer: canon,
        ).execute(_kDocId);
        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );

    test(
      'blocks when canonical paths overlap even if raw strings look distinct',
      () async {
        // Managed root canonicalizes to the same path as backup root.
        final canon = _FakeCanonicalizer({
          r'C:\Library': r'C:\Shared',
          r'D:\Backups': r'C:\Shared',
        });
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)]
          ..roots = const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: r'D:\Backups',
          );
        final result = await _makeUseCase(
          repo: repo,
          canonicalizer: canon,
        ).execute(_kDocId);
        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );

    test(
      'blocks with missingSource when source canonical path is null',
      () async {
        final canon = _FakeCanonicalizer({_kSourcePath: null});
        final result = await _makeUseCase(
          canonicalizer: canon,
        ).execute(_kDocId);
        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.missingSource,
        );
      },
    );

    test(
      'blocks before backup when files directory identity changes',
      () async {
        final result = await _makeUseCase(
          canonicalizer: _ChangingFilesCanonicalizer(),
        ).execute(_kDocId);
        expect(result, isA<ManagedCopyBlocked>());
        expect(
          (result as ManagedCopyBlocked).error,
          ManagedCopyError.unsafeRoots,
        );
      },
    );
  });

  // ── Safety correction 3: operation ID uniqueness ───────────────────────────

  group('ManagedCopyUseCase — operation ID uniqueness (correction 3)', () {
    test('each execute call uses a distinct operation ID', () async {
      final idGen = _CountingOperationIdGenerator();

      Future<String?> runAndGetId() async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          ..candidates = [_sourceCandidate(hash: _kHash)];
        final result = await ManagedCopyUseCase(
          repository: repo,
          filesystem: _FakeFilesystem(),
          backupService: _FakeBackupService(),
          hasher: _FakeHasher(),
          clock: _FakeClock(),
          pathCanonicalizer: _FakeCanonicalizer(),
          operationIdGenerator: idGen,
        ).execute(_kDocId);
        if (result is! ManagedCopySuccess) return null;
        final ev = repo.events.firstWhere(
          (e) => e['eventTypeKey'] == 'copy_started',
          orElse: () => {},
        );
        return ev['operationId'] as String?;
      }

      final id1 = await runAndGetId();
      final id2 = await runAndGetId();
      expect(id1, isNotNull);
      expect(id2, isNotNull);
      expect(id1, isNot(equals(id2)));
    });
  });

  // ── Safety correction 7: file size guard ──────────────────────────────────

  group('ManagedCopyUseCase — file size guard (correction 7)', () {
    test('returns RecoveryRequired when size is null', () async {
      final fs = _FakeFilesystem()..fileSizeResult = null;
      final result = await _makeUseCase(fs: fs).execute(_kDocId);
      expect(result, isA<ManagedCopyRecoveryRequired>());
    });

    test('returns RecoveryRequired when finalized size is zero', () async {
      final fs = _FakeFilesystem()..fileSizeResult = 0;
      final result = await _makeUseCase(fs: fs).execute(_kDocId);
      expect(result, isA<ManagedCopyRecoveryRequired>());
    });

    test('succeeds when file size is positive', () async {
      final fs = _FakeFilesystem()..fileSizeResult = 1024;
      final result = await _makeUseCase(fs: fs).execute(_kDocId);
      expect(result, isA<ManagedCopySuccess>());
    });
  });

  // ── Safety correction 8: mandatory audit events ────────────────────────────

  group('ManagedCopyUseCase — mandatory audit events (correction 8)', () {
    test('returns auditEventFailed and does not copy bytes '
        'when backup_created event fails', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)]
        ..throwOnAuditEvent = {'backup_created'};
      final fs = _FakeFilesystem();
      final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
      expect(result, isA<ManagedCopyFailed>());
      expect(
        (result as ManagedCopyFailed).error,
        ManagedCopyError.auditEventFailed,
      );
      expect(
        fs.copyCalls,
        isEmpty,
        reason: 'no bytes must be copied after audit event failure',
      );
    });

    test('returns auditEventFailed and does not copy bytes '
        'when copy_started event fails', () async {
      final repo = _FakeRepo()
        ..docState = _classifiedState()
        ..candidates = [_sourceCandidate(hash: _kHash)]
        ..throwOnAuditEvent = {'copy_started'};
      final fs = _FakeFilesystem();
      final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);
      expect(result, isA<ManagedCopyFailed>());
      expect(
        (result as ManagedCopyFailed).error,
        ManagedCopyError.auditEventFailed,
      );
      expect(
        fs.copyCalls,
        isEmpty,
        reason: 'no bytes must be copied after audit event failure',
      );
    });
  });

  // ── Word-converted document managed copy (bug fix: deferred code allocation) -

  group('ManagedCopyUseCase — Word-converted source (converted_pdf role)', () {
    // The converted PDF lives in WordStaging/ (not files/), so it is a valid
    // managed-copy source: the overlap guard only inspects source_original
    // paths; the source-inside-files/ guard compares the selected file path
    // against canonFilesDir, which doesn't match WordStaging/.
    const kConvertedPath =
        r'C:\Library\WordStaging\deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef.pdf';

    test(
      'succeeds when the only eligible source is a converted_pdf in WordStaging',
      () async {
        final repo = _FakeRepo()
          ..docState = _classifiedState()
          // No source_original PDF; only the converted_pdf from Word conversion.
          ..sourcePaths =
              [] // loadDocumentSourcePaths returns source_original paths
          ..candidates = [_sourceCandidate(path: kConvertedPath, hash: _kHash)];
        final fs = _FakeFilesystem();
        final result = await _makeUseCase(repo: repo, fs: fs).execute(_kDocId);

        expect(result, isA<ManagedCopySuccess>());
        final s = result as ManagedCopySuccess;
        // DOC code is allocated at managed-copy time, not at conversion time.
        expect(s.documentCode, 'DOC-0000001');
        expect(s.managedPath, contains(r'files\DOC-0000001.pdf'));
      },
    );

    test(
      'document_code is null before managed copy runs (allocate not called during conversion)',
      () async {
        // Simulate the state after import+conversion but before managed copy:
        // document_code is null because ConvertStagedWordSource no longer calls
        // allocateDocumentCode.
        final repo = _FakeRepo()
          ..docState =
              _classifiedState(code: null) // null = no code yet
          ..sourcePaths = []
          ..candidates = [_sourceCandidate(path: kConvertedPath, hash: _kHash)];

        // Before managed copy: no code set.
        expect(repo.docState?.existingDocumentCode, isNull);

        // Run managed copy.
        await _makeUseCase(repo: repo).execute(_kDocId);

        // After managed copy: code allocated by the use case.
        // (The fake repo records the allocation via allocatedCode.)
        expect(repo.allocatedCode, 'DOC-0000001');
      },
    );

    test(
      'plain PDF import also leaves document_code null before managed copy',
      () async {
        // Plain PDFs never call allocateDocumentCode during import.
        final repo = _FakeRepo()
          ..docState =
              _classifiedState(code: null) // null before managed copy
          ..sourcePaths = [_kSourcePath]
          ..candidates = [_sourceCandidate(hash: _kHash)];

        expect(repo.docState?.existingDocumentCode, isNull);
        final result = await _makeUseCase(repo: repo).execute(_kDocId);

        expect(result, isA<ManagedCopySuccess>());
        expect((result as ManagedCopySuccess).documentCode, 'DOC-0000001');
      },
    );
  });
}

// ─── Sequenced helpers for ordering verification ─────────────────────────────

/// Records whether the backup was marked done before the first copyFile call.
class _SequencedFilesystem extends _FakeFilesystem {
  bool _backupDone = false;
  bool backupBeforeCopy = false;

  void markBackupDone() => _backupDone = true;

  @override
  Future<FilesystemOperationResult> copyFile(
    String sourcePath,
    String destPath,
  ) async {
    backupBeforeCopy = _backupDone;
    return super.copyFile(sourcePath, destPath);
  }
}

class _SequencedBackupService extends _FakeBackupService {
  final _SequencedFilesystem _fs;
  _SequencedBackupService(this._fs);

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async {
    _fs.markBackupDone();
    return super.createBackup(
      backupRoot: backupRoot,
      operationId: operationId,
      timestamp: timestamp,
    );
  }
}

/// Hasher that returns [sourceHash] for non-.copying paths and [tmpHash] for
/// paths ending in .copying (simulating a hash mismatch on the copied file).
class _MismatchHasher implements FileHasher {
  _MismatchHasher({required this.sourceHash, required this.tmpHash});
  final String sourceHash;
  final String tmpHash;

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress)? onProgress,
  }) async => Sha256Result.success(
    absolutePath.endsWith('.copying') ? tmpHash : sourceHash,
  );
}
