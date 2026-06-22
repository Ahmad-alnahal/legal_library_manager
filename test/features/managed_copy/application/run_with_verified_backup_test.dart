// test/features/managed_copy/application/run_with_verified_backup_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/managed_copy/application/run_with_verified_backup.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/verified_backup_guard_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/database_backup_service.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/operation_id_generator.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _StubRepo implements ManagedCopyRepository {
  CopyRoots roots;
  final List<Map<String, Object?>> appendedEvents = [];
  bool throwOnAppend = false;

  _StubRepo({CopyRoots? roots})
    : roots =
          roots ??
          const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: kBackupRoot,
          );

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

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
    if (throwOnAppend) throw StateError('DB append failed');
    appendedEvents.add({
      'eventTypeKey': eventTypeKey,
      'operationId': operationId,
      'resultKey': resultKey,
      'destinationPath': destinationPath,
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _StubBackupService implements DatabaseBackupService {
  final BackupResult result;
  int callCount = 0;

  _StubBackupService(this.result);

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async {
    callCount++;
    return result;
  }
}

class _StubFs implements ManagedLibraryFilesystem {
  final bool directoryExists;

  const _StubFs({this.directoryExists = true});

  @override
  bool isExistingDirectory(String path) => directoryExists;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _StubOpGen implements OperationIdGenerator {
  @override
  String generate(DateTime now) => 'op-guard-test';
}

class _FixedClock extends Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 6, 22, 10, 0, 0);
}

/// Records the order of backup vs operation calls.
class _OrderedBackupService implements DatabaseBackupService {
  _OrderedBackupService({required this.result, required this.order});

  final BackupResult result;
  final List<String> order;

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async {
    order.add('backup');
    return result;
  }
}

// ── Constants & helpers ───────────────────────────────────────────────────────

const kBackupRoot = r'C:\Backups';
const kBackupPath =
    r'C:\Backups\legal_library_backup_2026-06-22_100000_op-guard-test.sqlite';

RunWithVerifiedBackup _build({
  _StubRepo? repo,
  DatabaseBackupService? backupService,
  bool directoryExists = true,
}) => RunWithVerifiedBackup(
  repository: repo ?? _StubRepo(),
  backupService:
      backupService ??
      _StubBackupService(const BackupSuccess(backupPath: kBackupPath)),
  filesystem: _StubFs(directoryExists: directoryExists),
  operationIdGenerator: _StubOpGen(),
  clock: _FixedClock(),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('RunWithVerifiedBackup', () {
    // ── Pre-condition: backup root not configured ─────────────────────────────

    test('returns backupNotConfigured when backup root is null', () async {
      final repo = _StubRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'C:\Library',
          backupRoot: null,
        ),
      );
      var opCalled = false;
      final result = await _build(repo: repo).call(() async {
        opCalled = true;
        return 'done';
      });

      expect(result, isA<GuardBackupNotConfigured<String>>());
      expect(opCalled, isFalse);
    });

    test(
      'returns backupNotConfigured when backup root is empty string',
      () async {
        final repo = _StubRepo(
          roots: const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: '',
          ),
        );
        var opCalled = false;
        final result = await _build(repo: repo).call(() async {
          opCalled = true;
          return 'done';
        });

        expect(result, isA<GuardBackupNotConfigured<String>>());
        expect(opCalled, isFalse);
      },
    );

    test(
      'returns backupNotConfigured when backup root is whitespace only',
      () async {
        final repo = _StubRepo(
          roots: const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: '   ',
          ),
        );
        final result = await _build(repo: repo).call(() async => 'done');
        expect(result, isA<GuardBackupNotConfigured<String>>());
      },
    );

    // ── Pre-condition: backup root directory missing ───────────────────────────

    test(
      'returns backupRootMissing when backup directory does not exist',
      () async {
        final svc = _StubBackupService(
          const BackupSuccess(backupPath: kBackupPath),
        );
        var opCalled = false;
        final result =
            await RunWithVerifiedBackup(
              repository: _StubRepo(),
              backupService: svc,
              filesystem: const _StubFs(directoryExists: false),
              operationIdGenerator: _StubOpGen(),
              clock: _FixedClock(),
            ).call(() async {
              opCalled = true;
              return 'done';
            });

        expect(result, isA<GuardBackupRootMissing<String>>());
        expect(opCalled, isFalse);
        expect(
          svc.callCount,
          0,
          reason: 'backup service must not be called when root is missing',
        );
      },
    );

    // ── Backup service failure ────────────────────────────────────────────────

    test(
      'returns backupFailed when backup service returns BackupFailure',
      () async {
        final svc = _StubBackupService(
          const BackupFailure(safeMessage: 'Disk full'),
        );
        var opCalled = false;
        final result = await _build(backupService: svc).call(() async {
          opCalled = true;
          return 'done';
        });

        expect(result, isA<GuardBackupFailed<String>>());
        expect(opCalled, isFalse);
        expect(
          svc.callCount,
          1,
          reason: 'backup service must be attempted once',
        );
      },
    );

    // ── Happy path: backup success then operation ─────────────────────────────

    test('backup is performed before the operation', () async {
      final order = <String>[];
      await RunWithVerifiedBackup(
        repository: _StubRepo(),
        backupService: _OrderedBackupService(
          result: const BackupSuccess(backupPath: kBackupPath),
          order: order,
        ),
        filesystem: const _StubFs(),
        operationIdGenerator: _StubOpGen(),
        clock: _FixedClock(),
      ).call(() async {
        order.add('operation');
        return 'done';
      });

      expect(order, ['backup', 'operation']);
    });

    test('operation is called exactly once on backup success', () async {
      var opCalls = 0;
      await _build().call(() async {
        opCalls++;
        return opCalls;
      });

      expect(opCalls, 1);
    });

    test(
      'returns operationSucceeded with typed value and backup path',
      () async {
        final result = await _build().call(() async => 42);

        expect(result, isA<GuardOperationSucceeded<int>>());
        final ok = result as GuardOperationSucceeded<int>;
        expect(ok.value, 42);
        expect(ok.backupPath, kBackupPath);
      },
    );

    test('operation result type flows through generic parameter', () async {
      final result = await _build().call<List<String>>(
        () async => ['a', 'b', 'c'],
      );

      expect(result, isA<GuardOperationSucceeded<List<String>>>());
      expect((result as GuardOperationSucceeded<List<String>>).value, [
        'a',
        'b',
        'c',
      ]);
    });

    // ── Operation failure after backup success ────────────────────────────────

    test(
      'returns operationFailed when operation throws, backup path preserved',
      () async {
        final error = Exception('bulk operation failed');
        final result = await _build().call<String>(() async => throw error);

        expect(result, isA<GuardOperationFailed<String>>());
        final failed = result as GuardOperationFailed<String>;
        expect(failed.error, same(error));
        expect(failed.backupPath, kBackupPath);
      },
    );

    test(
      'backup service is called exactly once even when operation throws',
      () async {
        final svc = _StubBackupService(
          const BackupSuccess(backupPath: kBackupPath),
        );
        await RunWithVerifiedBackup(
          repository: _StubRepo(),
          backupService: svc,
          filesystem: const _StubFs(),
          operationIdGenerator: _StubOpGen(),
          clock: _FixedClock(),
        ).call<void>(() async => throw Exception('op error'));

        expect(svc.callCount, 1);
      },
    );

    // ── Audit events ─────────────────────────────────────────────────────────

    test('appends backup_created/succeeded event on backup success', () async {
      final repo = _StubRepo();
      await RunWithVerifiedBackup(
        repository: repo,
        backupService: _StubBackupService(
          const BackupSuccess(backupPath: kBackupPath),
        ),
        filesystem: const _StubFs(),
        operationIdGenerator: _StubOpGen(),
        clock: _FixedClock(),
      ).call(() async => 'ok');

      expect(repo.appendedEvents, hasLength(1));
      final event = repo.appendedEvents.first;
      expect(event['eventTypeKey'], 'backup_created');
      expect(event['resultKey'], 'succeeded');
      expect(event['destinationPath'], kBackupPath);
    });

    test(
      'appends backup_created/failed event when backup service fails',
      () async {
        final repo = _StubRepo();
        await RunWithVerifiedBackup(
          repository: repo,
          backupService: _StubBackupService(
            const BackupFailure(safeMessage: 'IO error'),
          ),
          filesystem: const _StubFs(),
          operationIdGenerator: _StubOpGen(),
          clock: _FixedClock(),
        ).call<void>(() async {});

        expect(repo.appendedEvents, hasLength(1));
        final event = repo.appendedEvents.first;
        expect(event['eventTypeKey'], 'backup_created');
        expect(event['resultKey'], 'failed');
        expect(event['destinationPath'], isNull);
      },
    );

    test(
      'no audit event is appended when backup root is not configured',
      () async {
        final repo = _StubRepo(
          roots: const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: null,
          ),
        );
        await RunWithVerifiedBackup(
          repository: repo,
          backupService: _StubBackupService(
            const BackupSuccess(backupPath: kBackupPath),
          ),
          filesystem: const _StubFs(),
          operationIdGenerator: _StubOpGen(),
          clock: _FixedClock(),
        ).call(() async => 'done');

        expect(repo.appendedEvents, isEmpty);
      },
    );

    test(
      'no audit event is appended when backup root directory is missing',
      () async {
        final repo = _StubRepo();
        await RunWithVerifiedBackup(
          repository: repo,
          backupService: _StubBackupService(
            const BackupSuccess(backupPath: kBackupPath),
          ),
          filesystem: const _StubFs(directoryExists: false),
          operationIdGenerator: _StubOpGen(),
          clock: _FixedClock(),
        ).call(() async => 'done');

        expect(repo.appendedEvents, isEmpty);
      },
    );

    test('audit event failure does not mask the guard result', () async {
      final repo = _StubRepo()..throwOnAppend = true;
      final result = await RunWithVerifiedBackup(
        repository: repo,
        backupService: _StubBackupService(
          const BackupSuccess(backupPath: kBackupPath),
        ),
        filesystem: const _StubFs(),
        operationIdGenerator: _StubOpGen(),
        clock: _FixedClock(),
      ).call(() async => 99);

      expect(result, isA<GuardOperationSucceeded<int>>());
      expect((result as GuardOperationSucceeded<int>).value, 99);
    });

    // ── Result shape: no backup path on pre-check failures ───────────────────

    test(
      'GuardBackupNotConfigured carries no backup path (compile-time)',
      () async {
        final repo = _StubRepo(
          roots: const CopyRoots(
            managedLibraryRoot: r'C:\Library',
            backupRoot: null,
          ),
        );
        final result = await _build(repo: repo).call(() async => 'done');
        // Verify the shape — GuardBackupNotConfigured has no fields.
        expect(result, isA<GuardBackupNotConfigured<String>>());
      },
    );

    test(
      'GuardBackupRootMissing carries no backup path (compile-time)',
      () async {
        final result = await _build(
          directoryExists: false,
        ).call(() async => 'done');
        expect(result, isA<GuardBackupRootMissing<String>>());
      },
    );

    test('GuardBackupFailed carries no backup path (compile-time)', () async {
      final result = await _build(
        backupService: _StubBackupService(
          const BackupFailure(safeMessage: 'err'),
        ),
      ).call(() async => 'done');
      expect(result, isA<GuardBackupFailed<String>>());
    });
  });
}
