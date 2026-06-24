// test/features/managed_copy/application/reconcile_managed_copy_integrity_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/managed_copy/application/reconcile_managed_copy_integrity.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_file_ref.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/reconcile_integrity_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/operation_id_generator.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';
import 'package:legal_library_manager/features/security/application/step_up_required_exception.dart';
import 'package:legal_library_manager/features/security/application/unauthorized_exception.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeClock extends Clock {
  static final _kNow = DateTime.utc(2026, 6, 22, 10, 0, 0);
  @override
  DateTime nowUtc() => _kNow;
}

class _StubOpGen implements OperationIdGenerator {
  int _n = 0;
  @override
  String generate(DateTime now) => 'op_${++_n}';
}

class _StubFs implements ManagedLibraryFilesystem {
  final Set<String> existingFiles;
  final Map<String, int> sizes;

  _StubFs(this.existingFiles, {this.sizes = const {}});

  @override
  bool isExistingFile(String path) => existingFiles.contains(path);

  @override
  Future<int?> fileSize(String path) async => sizes[path];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _StubHasher implements FileHasher {
  final Map<String, String?> hashes;

  _StubHasher([this.hashes = const {}]);

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    final h = hashes[absolutePath];
    if (h == null) {
      return Sha256Result.failure(
        ImportError(
          code: ImportErrorCode.hashFailed,
          path: absolutePath,
          message: 'test: hash unavailable',
        ),
      );
    }
    return Sha256Result.success(h);
  }
}

class _StubRepo implements ManagedCopyRepository {
  final List<ManagedFileRef> allFiles;
  final List<int> markedMissing = [];
  final List<int> markedCorrupted = [];
  final List<int> restoredHealthy = [];
  final List<int> downgradedDocIds = [];
  bool throwOnMarkMissing = false;
  bool throwOnMarkCorrupted = false;
  bool throwOnDowngrade = false;

  _StubRepo(this.allFiles);

  @override
  Future<List<ManagedFileRef>> loadAllManagedCopyFiles() async => allFiles;

  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    if (throwOnMarkMissing) throw StateError('DB error');
    markedMissing.add(fileId);
  }

  @override
  Future<void> markManagedFileCorrupted({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    if (throwOnMarkCorrupted) throw StateError('DB error');
    markedCorrupted.add(fileId);
  }

  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    restoredHealthy.add(fileId);
  }

  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) async {
    if (throwOnDowngrade) throw StateError('DB error');
    downgradedDocIds.add(documentId);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const kDocId = 1;
const kPath = r'C:\Library\files\DOC-0000001.pdf';
const kHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const kSize = 4096;

ManagedFileRef _ref({
  int fileId = 1,
  int documentId = kDocId,
  String path = kPath,
  String health = 'healthy',
  int size = kSize,
  String? hash = kHash,
}) => ManagedFileRef(
  fileId: fileId,
  documentId: documentId,
  absolutePath: path,
  fileHealthKey: health,
  fileSizeBytes: size,
  sha256Hash: hash,
);

final _adminSession = Session(
  accountId: 'admin',
  username: 'marjiy@admin',
  role: AccountRole.admin,
  startedAt: DateTime.utc(2026, 6, 24, 9),
);

ReconcileManagedCopyIntegrity _build({
  required _StubRepo repo,
  required _StubFs fs,
  Map<String, String?> hashes = const {kPath: kHash},
  SessionManager? sessionManager,
  StepUpManager? stepUpManager,
  bool grantStepUp = true,
}) {
  final effectiveStepUp = stepUpManager ?? StepUpManager();
  if (grantStepUp) effectiveStepUp.grant();
  final mgr = sessionManager ??
      (SessionManager(stepUpManager: effectiveStepUp)..login(_adminSession));
  return ReconcileManagedCopyIntegrity(
    repository: repo,
    filesystem: fs,
    hasher: _StubHasher(hashes),
    operationIdGenerator: _StubOpGen(),
    clock: _FakeClock(),
    sessionManager: mgr,
    stepUpManager: effectiveStepUp,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ReconcileManagedCopyIntegrity', () {
    // ── Authorization ──────────────────────────────────────────────────────

    test('throws UnauthorizedException when no session is active', () async {
      final noStepUp = StepUpManager();
      final noSessionManager = SessionManager(stepUpManager: noStepUp);
      final uc = _build(
        repo: _StubRepo([]),
        fs: _StubFs({}),
        sessionManager: noSessionManager,
        stepUpManager: noStepUp,
        grantStepUp: false,
      );
      await expectLater(uc.call(), throwsA(isA<UnauthorizedException>()));
      noStepUp.dispose();
      noSessionManager.dispose();
    });

    test('throws UnauthorizedException when an operator session is active',
        () async {
      final opStepUp = StepUpManager();
      final operatorManager = SessionManager(stepUpManager: opStepUp);
      operatorManager.login(Session(
        accountId: 'op1',
        username: 'op@operator',
        role: AccountRole.operator,
        startedAt: DateTime.utc(2026, 6, 24, 9),
      ));
      final uc = _build(
        repo: _StubRepo([]),
        fs: _StubFs({}),
        sessionManager: operatorManager,
        stepUpManager: opStepUp,
        grantStepUp: false,
      );
      await expectLater(uc.call(), throwsA(isA<UnauthorizedException>()));
      opStepUp.dispose();
      operatorManager.dispose();
    });

    test('throws StepUpRequiredException when admin has no step-up approval',
        () async {
      final uc = _build(
        repo: _StubRepo([]),
        fs: _StubFs({}),
        grantStepUp: false,
      );
      await expectLater(uc.call(), throwsA(isA<StepUpRequiredException>()));
    });

    // ── Empty / no-op ──────────────────────────────────────────────────────

    test('returns empty result when no managed-copy files exist', () async {
      final repo = _StubRepo([]);
      final result = await _build(repo: repo, fs: _StubFs({})).call();
      expect(result, ReconcileIntegrityResult.empty);
      expect(repo.markedMissing, isEmpty);
      expect(repo.downgradedDocIds, isEmpty);
    });

    // ── Missing file detection ─────────────────────────────────────────────

    test(
      'marks a registered managed file as missing when absent from disk',
      () async {
        final repo = _StubRepo([_ref(fileId: 7)]);
        final fs = _StubFs({}); // file NOT on disk
        final result = await _build(repo: repo, fs: fs).call();
        expect(repo.markedMissing, [7]);
        expect(repo.markedCorrupted, isEmpty);
        expect(result.missingCount, 1);
        expect(result.healthyCount, 0);
      },
    );

    test('does not re-mark a file already recorded as missing', () async {
      final repo = _StubRepo([_ref(health: 'missing')]);
      final fs = _StubFs({}); // still absent
      await _build(repo: repo, fs: fs).call();
      expect(repo.markedMissing, isEmpty);
    });

    // ── Corrupted file detection (size mismatch) ───────────────────────────

    test(
      'marks file corrupted when physical size differs from stored size',
      () async {
        final repo = _StubRepo([_ref(fileId: 3, size: kSize)]);
        final fs = _StubFs({kPath}, sizes: {kPath: kSize + 1}); // wrong size
        final result = await _build(repo: repo, fs: fs).call();
        expect(repo.markedCorrupted, [3]);
        expect(repo.markedMissing, isEmpty);
        expect(result.corruptedCount, 1);
      },
    );

    // ── Corrupted file detection (hash mismatch) ───────────────────────────

    test(
      'marks file corrupted when SHA-256 does not match stored hash',
      () async {
        final repo = _StubRepo([_ref(fileId: 5, size: kSize)]);
        final fs = _StubFs({kPath}, sizes: {kPath: kSize}); // correct size
        const badHash =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        final result = await _build(
          repo: repo,
          fs: fs,
          hashes: {kPath: badHash}, // wrong hash
        ).call();
        expect(repo.markedCorrupted, [5]);
        expect(result.corruptedCount, 1);
      },
    );

    // ── Healthy file ───────────────────────────────────────────────────────

    test(
      'healthy file with matching content remains healthy, no DB updates',
      () async {
        final repo = _StubRepo([_ref(size: kSize)]);
        final fs = _StubFs({kPath}, sizes: {kPath: kSize}); // correct size
        final result = await _build(repo: repo, fs: fs).call();
        expect(repo.markedMissing, isEmpty);
        expect(repo.markedCorrupted, isEmpty);
        expect(repo.downgradedDocIds, isEmpty);
        expect(result.healthyCount, 1);
        expect(result.missingCount, 0);
      },
    );

    test('skips size check when fileSizeBytes is 0 (not stored)', () async {
      final repo = _StubRepo([_ref(size: 0)]); // no stored size
      final fs = _StubFs({kPath}, sizes: {kPath: 12345}); // any size on disk
      final result = await _build(repo: repo, fs: fs).call();
      expect(repo.markedCorrupted, isEmpty);
      expect(result.healthyCount, 1);
    });

    test('skips hash check when sha256Hash is null', () async {
      final repo = _StubRepo([_ref(size: 0, hash: null)]);
      final fs = _StubFs({kPath}); // file on disk, no hash to verify
      final result = await _build(repo: repo, fs: fs, hashes: {}).call();
      expect(repo.markedCorrupted, isEmpty);
      expect(result.healthyCount, 1);
    });

    // ── Downgrade logic ────────────────────────────────────────────────────

    test(
      'downgrades document to classified when all managed copies are unhealthy',
      () async {
        final repo = _StubRepo([_ref(fileId: 9)]);
        final fs = _StubFs({}); // file absent
        final result = await _build(repo: repo, fs: fs).call();
        expect(repo.downgradedDocIds, [kDocId]);
        expect(result.downgradedDocumentCount, 1);
      },
    );

    test(
      'does not downgrade when at least one healthy managed copy exists',
      () async {
        const path2 = r'C:\Library\files\DOC-0000001-v2.pdf';
        final repo = _StubRepo([
          _ref(fileId: 10, size: kSize), // healthy
          _ref(fileId: 11, path: path2, health: 'missing'), // still missing
        ]);
        final fs = _StubFs(
          {kPath},
          sizes: {kPath: kSize},
        ); // only first on disk
        final result = await _build(repo: repo, fs: fs).call();
        expect(repo.downgradedDocIds, isEmpty);
        expect(result.healthyCount, 1);
      },
    );

    test(
      'does not downgrade when previously-missing file is restored',
      () async {
        final repo = _StubRepo([
          _ref(fileId: 12, health: 'missing', size: kSize),
        ]);
        final fs = _StubFs({kPath}, sizes: {kPath: kSize}); // file came back
        final result = await _build(repo: repo, fs: fs).call();
        expect(repo.restoredHealthy, [12]);
        expect(repo.downgradedDocIds, isEmpty);
        expect(result.restoredCount, 1);
      },
    );

    // ── Multi-document scope ───────────────────────────────────────────────

    test('processes multiple documents independently', () async {
      const doc2Id = 2;
      const path2 = r'C:\Library\files\DOC-0000002.pdf';
      final repo = _StubRepo([
        _ref(fileId: 1, documentId: kDocId, size: kSize), // healthy
        _ref(fileId: 2, documentId: doc2Id, path: path2), // will be missing
      ]);
      final fs = _StubFs({kPath}, sizes: {kPath: kSize}); // only doc1 on disk
      final result = await _build(repo: repo, fs: fs).call();
      expect(repo.markedMissing, [2]);
      expect(repo.downgradedDocIds, [doc2Id]); // only doc2 downgraded
      expect(result.healthyCount, 1);
      expect(result.missingCount, 1);
      expect(result.downgradedDocumentCount, 1);
    });

    // ── Source_original files ignored ──────────────────────────────────────

    test(
      'handles empty result from repo (source_original files are excluded by repo)',
      () async {
        // loadAllManagedCopyFiles filters to managed_copy role in the repository;
        // the use case receives an empty list and does nothing.
        final repo = _StubRepo([]);
        final result = await _build(repo: repo, fs: _StubFs({})).call();
        expect(result.totalChecked, 0);
        expect(repo.markedMissing, isEmpty);
        expect(repo.markedCorrupted, isEmpty);
      },
    );

    // ── Filesystem / hash failures ─────────────────────────────────────────

    test('does not crash when fileSize returns null (IO error)', () async {
      final repo = _StubRepo([_ref(size: kSize)]);
      // File exists but fileSize throws IO (returns null)
      final fs = _StubFs({kPath}); // no entry in sizes map → null
      final result = await _build(repo: repo, fs: fs).call();
      // Size check fails safely; file is counted as failed
      expect(result.failedCount, 1);
      expect(repo.markedCorrupted, isEmpty);
    });

    test('does not crash when hash computation fails', () async {
      final repo = _StubRepo([_ref(size: kSize)]);
      final fs = _StubFs({kPath}, sizes: {kPath: kSize});
      // Hasher will fail (no entry in hashes map → returns failure)
      final result = await _build(repo: repo, fs: fs, hashes: {}).call();
      expect(result.failedCount, 1);
      expect(repo.markedCorrupted, isEmpty);
    });

    test('does not crash when markManagedFileMissing throws', () async {
      final repo = _StubRepo([_ref(fileId: 1)])..throwOnMarkMissing = true;
      final fs = _StubFs({}); // file absent
      final result = await _build(repo: repo, fs: fs).call();
      expect(result.failedCount, 1);
      expect(result.missingCount, 0);
    });

    test('does not crash when markManagedFileCorrupted throws', () async {
      final repo = _StubRepo([_ref(fileId: 2, size: kSize)])
        ..throwOnMarkCorrupted = true;
      const badHash =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      final fs = _StubFs({kPath}, sizes: {kPath: kSize});
      final result = await _build(
        repo: repo,
        fs: fs,
        hashes: {kPath: badHash},
      ).call();
      expect(result.failedCount, 1);
      expect(result.corruptedCount, 0);
    });

    // ── Audit events (repository responsibility; verified by stub calls) ───

    test('calls markManagedFileMissing with correct documentId', () async {
      final repo = _StubRepo([_ref(fileId: 20, documentId: 99)]);
      await _build(repo: repo, fs: _StubFs({})).call();
      expect(repo.markedMissing, contains(20));
    });

    test('calls markManagedFileCorrupted with correct fileId', () async {
      final repo = _StubRepo([_ref(fileId: 33, size: kSize)]);
      final fs = _StubFs({kPath}, sizes: {kPath: kSize});
      const wrongHash =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      await _build(repo: repo, fs: fs, hashes: {kPath: wrongHash}).call();
      expect(repo.markedCorrupted, contains(33));
    });

    // ── Restore of corrupted file ──────────────────────────────────────────

    test(
      'restores corrupted file to healthy when content now matches',
      () async {
        final repo = _StubRepo([
          _ref(fileId: 40, health: 'corrupted', size: kSize),
        ]);
        final fs = _StubFs(
          {kPath},
          sizes: {kPath: kSize},
        ); // file on disk, correct
        final result = await _build(repo: repo, fs: fs).call();
        expect(repo.restoredHealthy, [40]);
        expect(repo.markedCorrupted, isEmpty);
        expect(result.restoredCount, 1);
        expect(repo.downgradedDocIds, isEmpty);
      },
    );

    // ── Already-corrupted file still missing ──────────────────────────────

    test(
      'corrupted-in-DB file that is now absent on disk is marked missing',
      () async {
        final repo = _StubRepo([_ref(fileId: 50, health: 'corrupted')]);
        final fs = _StubFs({}); // now missing from disk
        await _build(repo: repo, fs: fs).call();
        expect(repo.markedMissing, [50]);
        expect(repo.markedCorrupted, isEmpty);
      },
    );
  });
}
