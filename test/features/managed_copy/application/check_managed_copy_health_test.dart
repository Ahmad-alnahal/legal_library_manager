// test/features/managed_copy/application/check_managed_copy_health_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/managed_copy/application/check_managed_copy_health.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_file_ref.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/operation_id_generator.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeClock extends Clock {
  static final _kNow = DateTime.utc(2026, 6, 17, 12, 0, 0);
  @override
  DateTime nowUtc() => _kNow;
}

class _StubOperationIdGenerator implements OperationIdGenerator {
  int _counter = 0;
  @override
  String generate(DateTime now) => 'op_test_${++_counter}';
}

class _StubFilesystem implements ManagedLibraryFilesystem {
  final Set<String> existingFiles;
  final Map<String, int> sizes;
  _StubFilesystem(this.existingFiles, {this.sizes = const {}});

  @override
  bool isExistingFile(String path) => existingFiles.contains(path);

  @override
  Future<int?> fileSize(String path) async => sizes[path];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _StubHasher implements FileHasher {
  _StubHasher([this.hashes = const {}]);

  final Map<String, String?> hashes;

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    final hash = hashes[absolutePath];
    if (hash == null) {
      return Sha256Result.failure(
        ImportError(
          code: ImportErrorCode.hashFailed,
          path: absolutePath,
          message: 'test hash unavailable',
        ),
      );
    }
    return Sha256Result.success(hash);
  }
}

class _StubRepository implements ManagedCopyRepository {
  final List<ManagedFileRef> managedFiles;
  final List<({int fileId, String operationId})> markedMissing = [];
  final List<({int fileId, String operationId})> restoredHealthy = [];
  final List<int> downgradedDocIds = [];
  bool throwOnMark = false;

  _StubRepository(this.managedFiles);

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
    if (throwOnMark) throw StateError('DB error');
    markedMissing.add((fileId: fileId, operationId: operationId));
  }

  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    restoredHealthy.add((fileId: fileId, operationId: operationId));
  }

  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) async {
    downgradedDocIds.add(documentId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  const int kDocId = 42;
  const String kPath = r'C:\Library\files\DOC-0000001.pdf';
  const kHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  CheckManagedCopyHealth build({
    required _StubRepository repo,
    required _StubFilesystem fs,
  }) => CheckManagedCopyHealth(
    repository: repo,
    filesystem: fs,
    hasher: _StubHasher({kPath: kHash}),
    operationIdGenerator: _StubOperationIdGenerator(),
    clock: _FakeClock(),
  );

  ManagedFileRef ref({
    int fileId = 1,
    String path = kPath,
    String health = FileHealthKey.healthy,
    int size = 2048,
    String? hash = kHash,
  }) => ManagedFileRef(
    fileId: fileId,
    documentId: kDocId,
    absolutePath: path,
    fileHealthKey: health,
    fileSizeBytes: size,
    sha256Hash: hash,
  );

  test('returns notApplicable when no managed-copy records exist', () async {
    final repo = _StubRepository([]);
    final fs = _StubFilesystem({kPath});
    final result = await build(repo: repo, fs: fs).call(kDocId);
    expect(result, CheckManagedCopyHealthResult.notApplicable);
    expect(repo.markedMissing, isEmpty);
    expect(repo.downgradedDocIds, isEmpty);
  });

  test(
    'returns healthy when all managed-copy files are physically present',
    () async {
      final ref = ManagedFileRef(
        fileId: 1,
        documentId: kDocId,
        absolutePath: kPath,
        fileHealthKey: FileHealthKey.healthy,
      );
      final repo = _StubRepository([ref]);
      final fs = _StubFilesystem({kPath}); // file IS on disk
      final result = await build(repo: repo, fs: fs).call(kDocId);
      expect(result, CheckManagedCopyHealthResult.healthy);
      expect(repo.markedMissing, isEmpty);
      expect(repo.downgradedDocIds, isEmpty);
    },
  );

  test(
    'returns missingReconciled and updates DB when managed file is physically absent',
    () async {
      final ref = ManagedFileRef(
        fileId: 7,
        documentId: kDocId,
        absolutePath: kPath,
        fileHealthKey: FileHealthKey.healthy,
      );
      final repo = _StubRepository([ref]);
      final fs = _StubFilesystem({}); // file NOT on disk
      final result = await build(repo: repo, fs: fs).call(kDocId);
      expect(result, CheckManagedCopyHealthResult.missingReconciled);
      expect(repo.markedMissing.length, 1);
      expect(repo.markedMissing.first.fileId, 7);
      expect(repo.downgradedDocIds, [kDocId]);
    },
  );

  test(
    'returns alreadyMissing when all managed-copy rows are already marked missing',
    () async {
      final ref = ManagedFileRef(
        fileId: 3,
        documentId: kDocId,
        absolutePath: kPath,
        fileHealthKey: FileHealthKey.missing, // already marked
      );
      final repo = _StubRepository([ref]);
      final fs = _StubFilesystem({}); // irrelevant — never checked
      final result = await build(repo: repo, fs: fs).call(kDocId);
      expect(result, CheckManagedCopyHealthResult.alreadyMissing);
      expect(repo.markedMissing, isEmpty);
      expect(repo.downgradedDocIds, [kDocId]);
    },
  );

  test(
    'restores a missing row when the physical file matches stored metadata',
    () async {
      final missing = ref(fileId: 13, health: FileHealthKey.missing);
      final repo = _StubRepository([missing]);
      final fs = _StubFilesystem({kPath}, sizes: {kPath: 2048});

      final result = await build(repo: repo, fs: fs).call(kDocId);

      expect(result, CheckManagedCopyHealthResult.missingReconciled);
      expect(repo.restoredHealthy.length, 1);
      expect(repo.restoredHealthy.first.fileId, 13);
      expect(repo.markedMissing, isEmpty);
      expect(repo.downgradedDocIds, isEmpty);
    },
  );

  test(
    'does not downgrade when another managed copy is still physically present',
    () async {
      final present = ManagedFileRef(
        fileId: 11,
        documentId: kDocId,
        absolutePath: kPath,
        fileHealthKey: FileHealthKey.healthy,
      );
      const missingPath = r'C:\Library\files\DOC-0000001-old.pdf';
      final gone = ManagedFileRef(
        fileId: 12,
        documentId: kDocId,
        absolutePath: missingPath,
        fileHealthKey: FileHealthKey.healthy,
      );
      final repo = _StubRepository([present, gone]);
      final fs = _StubFilesystem({kPath});
      final result = await build(repo: repo, fs: fs).call(kDocId);
      expect(result, CheckManagedCopyHealthResult.missingReconciled);
      expect(repo.markedMissing.length, 1);
      expect(repo.markedMissing.first.fileId, 12);
      expect(repo.downgradedDocIds, isEmpty);
    },
  );

  test(
    'reconciles only non-missing rows and ignores already-missing rows',
    () async {
      final alreadyMissing = ManagedFileRef(
        fileId: 1,
        documentId: kDocId,
        absolutePath: r'C:\Library\files\OLD.pdf',
        fileHealthKey: FileHealthKey.missing,
      );
      const newPath = r'C:\Library\files\DOC-0000001-v2.pdf';
      final healthyButGone = ManagedFileRef(
        fileId: 2,
        documentId: kDocId,
        absolutePath: newPath,
        fileHealthKey: FileHealthKey.healthy,
      );
      final repo = _StubRepository([alreadyMissing, healthyButGone]);
      final fs = _StubFilesystem({}); // neither file on disk
      final result = await build(repo: repo, fs: fs).call(kDocId);
      expect(result, CheckManagedCopyHealthResult.missingReconciled);
      // Only the non-missing (healthy) row should be marked.
      expect(repo.markedMissing.length, 1);
      expect(repo.markedMissing.first.fileId, 2);
      expect(repo.downgradedDocIds, [kDocId]);
    },
  );

  test('returns reconciliationFailed when DB mark throws', () async {
    final ref = ManagedFileRef(
      fileId: 5,
      documentId: kDocId,
      absolutePath: kPath,
      fileHealthKey: FileHealthKey.healthy,
    );
    final repo = _StubRepository([ref])..throwOnMark = true;
    final fs = _StubFilesystem({}); // file NOT on disk
    final result = await build(repo: repo, fs: fs).call(kDocId);
    expect(result, CheckManagedCopyHealthResult.reconciliationFailed);
  });

  test('does not call downgrade when file is present on disk', () async {
    final ref = ManagedFileRef(
      fileId: 9,
      documentId: kDocId,
      absolutePath: kPath,
      fileHealthKey: FileHealthKey.healthy,
    );
    final repo = _StubRepository([ref]);
    final fs = _StubFilesystem({kPath}); // file IS on disk
    await build(repo: repo, fs: fs).call(kDocId);
    expect(repo.downgradedDocIds, isEmpty);
  });
}
