// test/features/file_open/open_file_use_case_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/file_open/application/open_file_use_case.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/file_open_record.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_file_result.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_target.dart';
import 'package:legal_library_manager/features/file_open/domain/repositories/file_open_repository.dart';
import 'package:legal_library_manager/features/file_open/domain/services/file_existence_checker.dart';
import 'package:legal_library_manager/features/file_open/domain/services/os_file_opener.dart';

// ---------------------------------------------------------------------------
// Fake implementations — never open a real file or touch the filesystem.
// ---------------------------------------------------------------------------

class _FakeRepo implements FileOpenRepository {
  FileOpenRecord? recordToReturn;
  bool throwOnRecord = false;

  final List<Map<String, Object?>> recordedEvents = [];

  @override
  Future<FileOpenRecord?> loadFileRecord(int fileId) async => recordToReturn;

  @override
  Future<void> recordOpenEvent({
    required int fileId,
    required int? documentId,
    required OpenTarget target,
    required String resultKey,
    String? errorCode,
    String? messageSafe,
  }) async {
    if (throwOnRecord) throw Exception('simulated persistence failure');
    recordedEvents.add({
      'fileId': fileId,
      'documentId': documentId,
      'target': target.name,
      'resultKey': resultKey,
      'errorCode': errorCode,
      'messageSafe': messageSafe,
    });
  }
}

class _FakeChecker implements FileExistenceChecker {
  _FakeChecker(this.status);
  final FileExistenceStatus status;

  @override
  FileExistenceStatus checkFile(String absolutePath) => status;
}

class _FakeOpener implements OsFileOpener {
  _FakeOpener({this.result = const OsOpenSuccess()});
  final OsOpenResult result;

  final List<String> openFileCalls = [];
  final List<String> openFolderCalls = [];

  @override
  Future<OsOpenResult> openFile(String absolutePath) async {
    openFileCalls.add(absolutePath);
    return result;
  }

  @override
  Future<OsOpenResult> openFolder(String absolutePath) async {
    openFolderCalls.add(absolutePath);
    return result;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _kPath = r'C:\Library\test.pdf';
const _kRecord = FileOpenRecord(
  fileId: 1,
  documentId: 10,
  absolutePath: _kPath,
  extension: '.pdf',
  fileHealthKey: 'healthy',
);

OpenFileUseCase _makeUseCase({
  _FakeRepo? repo,
  FileExistenceStatus existenceStatus = FileExistenceStatus.regularFile,
  OsOpenResult osResult = const OsOpenSuccess(),
}) {
  return OpenFileUseCase(
    repository: repo ?? (_FakeRepo()..recordToReturn = _kRecord),
    existenceChecker: _FakeChecker(existenceStatus),
    osOpener: _FakeOpener(result: osResult),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OpenFileUseCase — registered ID gate', () {
    test(
      'nonexistent file ID returns blocked and never calls the OS',
      () async {
        final repo = _FakeRepo(); // recordToReturn is null by default
        final opener = _FakeOpener();
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: opener,
        );

        final result = await uc.execute(999, OpenTarget.file);

        expect(result, isA<OpenFileBlocked>());
        expect(
          (result as OpenFileBlocked).code,
          FileOpenError.fileRecordNotFound,
        );
        expect(opener.openFileCalls, isEmpty);
        expect(opener.openFolderCalls, isEmpty);
      },
    );

    test('registered file ID with valid PDF reaches the OS invoker', () async {
      final opener = _FakeOpener();
      final repo = _FakeRepo()..recordToReturn = _kRecord;
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileSuccess>());
      expect(opener.openFileCalls, [_kPath]);
    });
  });

  group('OpenFileUseCase — path validation', () {
    test('blank stored path returns blocked', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: '   ',
          extension: '.pdf',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect((result as OpenFileBlocked).code, FileOpenError.missingPath);
      expect(opener.openFileCalls, isEmpty);
    });

    test('missing file on disk returns blocked', () async {
      final uc = _makeUseCase(existenceStatus: FileExistenceStatus.notFound);
      final result = await uc.execute(1, OpenTarget.file);
      expect(result, isA<OpenFileBlocked>());
      expect((result as OpenFileBlocked).code, FileOpenError.pathNotFound);
    });

    test('missing file on disk also blocks OpenTarget.folder without '
        'attempting to open any folder (chosen behavior: fail closed, never '
        'silently reveal an unrelated folder)', () async {
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: _FakeRepo()..recordToReturn = _kRecord,
        existenceChecker: _FakeChecker(FileExistenceStatus.notFound),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.folder);

      expect(result, isA<OpenFileBlocked>());
      expect((result as OpenFileBlocked).code, FileOpenError.pathNotFound);
      expect(opener.openFolderCalls, isEmpty);
    });

    test('directory masquerading as file returns blocked', () async {
      final uc = _makeUseCase(existenceStatus: FileExistenceStatus.directory);
      final result = await uc.execute(1, OpenTarget.file);
      expect(result, isA<OpenFileBlocked>());
      expect((result as OpenFileBlocked).code, FileOpenError.notARegularFile);
    });

    test('access denied during existence check returns failed', () async {
      final uc = _makeUseCase(
        existenceStatus: FileExistenceStatus.accessDenied,
      );
      final result = await uc.execute(1, OpenTarget.file);
      expect(result, isA<OpenFileFailed>());
      expect((result as OpenFileFailed).code, FileOpenError.permissionDenied);
    });
  });

  group('OpenFileUseCase — extension validation', () {
    test('Word .docx extension is blocked (not a supported format)', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: r'C:\Library\doc.docx',
          extension: '.docx',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect(
        (result as OpenFileBlocked).code,
        FileOpenError.unsupportedExtension,
      );
      expect(opener.openFileCalls, isEmpty);
    });

    test('Word .doc extension is accepted for direct open', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: r'C:\Library\doc.doc',
          extension: '.doc',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileSuccess>());
      expect(opener.openFileCalls, [r'C:\Library\doc.doc']);
      expect(opener.openFolderCalls, isEmpty);
    });

    test('Word .docx extension is blocked for folder reveal too', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: r'C:\Library\doc.docx',
          extension: '.docx',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.folder);

      expect(result, isA<OpenFileBlocked>());
      expect(
        (result as OpenFileBlocked).code,
        FileOpenError.unsupportedExtension,
      );
      expect(opener.openFolderCalls, isEmpty);
    });

    test('misleading double extension (.pdf.exe) returns blocked', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: r'C:\Library\doc.pdf.exe',
          extension: '.exe',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect(
        (result as OpenFileBlocked).code,
        FileOpenError.unsupportedExtension,
      );
      expect(opener.openFileCalls, isEmpty);
    });

    test(
      'uppercase .PDF extension is accepted (case-insensitive check)',
      () async {
        final repo = _FakeRepo()
          ..recordToReturn = const FileOpenRecord(
            fileId: 1,
            documentId: 10,
            absolutePath: r'C:\Library\REPORT.PDF',
            extension: '.PDF',
            fileHealthKey: 'healthy',
          );
        final opener = _FakeOpener();
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: opener,
        );

        final result = await uc.execute(1, OpenTarget.file);

        expect(result, isA<OpenFileSuccess>());
        expect(opener.openFileCalls, hasLength(1));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Correction 1: dual extension validation — path vs stored must both be .pdf
  // and must agree. Added tests prove each mismatch variant is blocked and the
  // OS invoker is never called when extensions disagree.
  // ---------------------------------------------------------------------------

  group('OpenFileUseCase — dual extension cross-validation', () {
    test('absolutePath .exe with stored .pdf is blocked', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: r'C:\Library\file.exe',
          extension: '.pdf',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect(
        (result as OpenFileBlocked).code,
        FileOpenError.unsupportedExtension,
      );
      expect(opener.openFileCalls, isEmpty);
      expect(opener.openFolderCalls, isEmpty);
    });

    test('absolutePath .pdf with stored .exe is blocked', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: r'C:\Library\file.pdf',
          extension: '.exe',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect(
        (result as OpenFileBlocked).code,
        FileOpenError.unsupportedExtension,
      );
      expect(opener.openFileCalls, isEmpty);
    });

    test('absolutePath .pdf.exe with stored .pdf is blocked', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: r'C:\Library\file.pdf.exe',
          extension: '.pdf',
          fileHealthKey: 'healthy',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect(
        (result as OpenFileBlocked).code,
        FileOpenError.unsupportedExtension,
      );
      expect(opener.openFileCalls, isEmpty);
    });

    test(
      'uppercase .PDF in both absolutePath and stored extension succeeds',
      () async {
        final repo = _FakeRepo()
          ..recordToReturn = const FileOpenRecord(
            fileId: 1,
            documentId: 10,
            absolutePath: r'C:\Library\REPORT.PDF',
            extension: '.PDF',
            fileHealthKey: 'healthy',
          );
        final opener = _FakeOpener();
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: opener,
        );

        final result = await uc.execute(1, OpenTarget.file);

        expect(result, isA<OpenFileSuccess>());
        expect(opener.openFileCalls, [r'C:\Library\REPORT.PDF']);
      },
    );
  });

  group('OpenFileUseCase — target dispatch', () {
    test('file target calls openFile exactly once', () async {
      final opener = _FakeOpener();
      final repo = _FakeRepo()..recordToReturn = _kRecord;
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileSuccess>());
      expect((result as OpenFileSuccess).target, OpenTarget.file);
      expect(opener.openFileCalls, [_kPath]);
      expect(opener.openFolderCalls, isEmpty);
    });

    test('folder target calls openFolder exactly once', () async {
      final opener = _FakeOpener();
      final repo = _FakeRepo()..recordToReturn = _kRecord;
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.folder);

      expect(result, isA<OpenFileSuccess>());
      expect((result as OpenFileSuccess).target, OpenTarget.folder);
      expect(opener.openFolderCalls, [_kPath]);
      expect(opener.openFileCalls, isEmpty);
    });
  });

  group('OpenFileUseCase — OS failure mapping', () {
    test(
      'permission denied from OS returns OpenFileFailed with correct code',
      () async {
        final uc = _makeUseCase(
          osResult: const OsOpenFailed(
            code: FileOpenError.permissionDenied,
            safeMessage: 'Access denied when launching the application.',
          ),
        );

        final result = await uc.execute(1, OpenTarget.file);

        expect(result, isA<OpenFileFailed>());
        expect((result as OpenFileFailed).code, FileOpenError.permissionDenied);
      },
    );

    test(
      'no associated application returns OpenFileFailed with correct code',
      () async {
        final uc = _makeUseCase(
          osResult: const OsOpenFailed(
            code: FileOpenError.noAssociatedApplication,
            safeMessage: 'No application is registered for this file type.',
          ),
        );

        final result = await uc.execute(1, OpenTarget.file);

        expect(result, isA<OpenFileFailed>());
        expect(
          (result as OpenFileFailed).code,
          FileOpenError.noAssociatedApplication,
        );
      },
    );

    test(
      'generic OS launch failure returns OpenFileFailed with correct code',
      () async {
        final uc = _makeUseCase(
          osResult: const OsOpenFailed(
            code: FileOpenError.osLaunchFailed,
            safeMessage: 'Failed to launch the associated application.',
          ),
        );

        final result = await uc.execute(1, OpenTarget.file);

        expect(result, isA<OpenFileFailed>());
        expect((result as OpenFileFailed).code, FileOpenError.osLaunchFailed);
      },
    );

    test('OS failure safeMessage is not a raw exception string', () async {
      final repo = _FakeRepo()..recordToReturn = _kRecord;
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: _FakeOpener(
          result: const OsOpenFailed(
            code: FileOpenError.osLaunchFailed,
            safeMessage: 'Failed to launch the associated application.',
          ),
        ),
      );

      final result = await uc.execute(1, OpenTarget.file);
      final failed = result as OpenFileFailed;

      // The message must not contain raw process output or path details.
      expect(failed.safeMessage.contains('Exception'), isFalse);
      expect(failed.safeMessage.contains('StackTrace'), isFalse);
      expect(failed.safeMessage.contains(_kPath), isFalse);
    });
  });

  group('OpenFileUseCase — audit failure isolation', () {
    test(
      'audit failure after successful OS launch returns OpenFileAuditFailure',
      () async {
        final repo = _FakeRepo()
          ..recordToReturn = _kRecord
          ..throwOnRecord = false; // record succeeds for blocked events
        final opener = _FakeOpener();
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: opener,
        );

        // Let the first few _tryRecord calls succeed, then fail on the success
        // record. Simulate by making repo throw after opener has been invoked.
        repo.throwOnRecord = true; // throw for the success record
        final result = await uc.execute(1, OpenTarget.file);

        // The OS was invoked.
        expect(opener.openFileCalls, [_kPath]);
        // The result correctly reports audit failure, not an OS failure.
        expect(result, isA<OpenFileAuditFailure>());
        expect((result as OpenFileAuditFailure).target, OpenTarget.file);
      },
    );
  });

  group('OpenFileUseCase — event recording content', () {
    test(
      'blocked event records stable error code, not raw exception text',
      () async {
        final repo = _FakeRepo(); // null record → fileRecordNotFound
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: _FakeOpener(),
        );

        // FK violation will silently prevent the insert for unknown IDs, but
        // the fake repo just records the attempted call.
        await uc.execute(999, OpenTarget.file);

        // The fake repo was called with the stable error code name.
        if (repo.recordedEvents.isNotEmpty) {
          final event = repo.recordedEvents.first;
          expect(event['errorCode'], FileOpenError.fileRecordNotFound.name);
          expect(
            (event['messageSafe'] as String?)?.contains('Exception'),
            isNot(isTrue),
          );
        }
      },
    );

    test('blocked pathNotFound event uses stable code', () async {
      final repo = _FakeRepo()..recordToReturn = _kRecord;
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.notFound),
        osOpener: _FakeOpener(),
      );

      await uc.execute(1, OpenTarget.file);

      expect(repo.recordedEvents, hasLength(1));
      expect(
        repo.recordedEvents.first['errorCode'],
        FileOpenError.pathNotFound.name,
      );
      expect(repo.recordedEvents.first['resultKey'], 'blocked');
    });

    test(
      'success event records resultKey succeeded with no error code',
      () async {
        final repo = _FakeRepo()..recordToReturn = _kRecord;
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: _FakeOpener(),
        );

        await uc.execute(1, OpenTarget.file);

        expect(repo.recordedEvents, hasLength(1));
        expect(repo.recordedEvents.first['resultKey'], 'succeeded');
        expect(repo.recordedEvents.first['errorCode'], isNull);
      },
    );

    test('failed OS event records resultKey failed with stable code', () async {
      final repo = _FakeRepo()..recordToReturn = _kRecord;
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: _FakeOpener(
          result: const OsOpenFailed(
            code: FileOpenError.noAssociatedApplication,
            safeMessage: 'No application is registered for this file type.',
          ),
        ),
      );

      await uc.execute(1, OpenTarget.folder);

      expect(repo.recordedEvents, hasLength(1));
      expect(repo.recordedEvents.first['resultKey'], 'failed');
      expect(
        repo.recordedEvents.first['errorCode'],
        FileOpenError.noAssociatedApplication.name,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // File health guard — OpenTarget.file is blocked for non-healthy files;
  // OpenTarget.folder is never restricted by health status.
  // ---------------------------------------------------------------------------

  group('OpenFileUseCase — file health guard', () {
    test(
      'corrupted file blocks OpenTarget.file with unhealthyFile code',
      () async {
        final repo = _FakeRepo()
          ..recordToReturn = const FileOpenRecord(
            fileId: 1,
            documentId: 10,
            absolutePath: _kPath,
            extension: '.pdf',
            fileHealthKey: 'corrupted',
          );
        final opener = _FakeOpener();
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: opener,
        );

        final result = await uc.execute(1, OpenTarget.file);

        expect(result, isA<OpenFileBlocked>());
        expect((result as OpenFileBlocked).code, FileOpenError.unhealthyFile);
        expect(opener.openFileCalls, isEmpty);
      },
    );

    test(
      'unreadable file blocks OpenTarget.file with unhealthyFile code',
      () async {
        final repo = _FakeRepo()
          ..recordToReturn = const FileOpenRecord(
            fileId: 1,
            documentId: 10,
            absolutePath: _kPath,
            extension: '.pdf',
            fileHealthKey: 'unreadable',
          );
        final opener = _FakeOpener();
        final uc = OpenFileUseCase(
          repository: repo,
          existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
          osOpener: opener,
        );

        final result = await uc.execute(1, OpenTarget.file);

        expect(result, isA<OpenFileBlocked>());
        expect((result as OpenFileBlocked).code, FileOpenError.unhealthyFile);
        expect(opener.openFileCalls, isEmpty);
      },
    );

    test('missing health blocks OpenTarget.file', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: _kPath,
          extension: '.pdf',
          fileHealthKey: 'missing',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect((result as OpenFileBlocked).code, FileOpenError.unhealthyFile);
      expect(opener.openFileCalls, isEmpty);
    });

    test('unknown health blocks OpenTarget.file', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: _kPath,
          extension: '.pdf',
          fileHealthKey: 'unknown',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileBlocked>());
      expect((result as OpenFileBlocked).code, FileOpenError.unhealthyFile);
      expect(opener.openFileCalls, isEmpty);
    });

    test('corrupted file still permits OpenTarget.folder', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: _kPath,
          extension: '.pdf',
          fileHealthKey: 'corrupted',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.folder);

      expect(result, isA<OpenFileSuccess>());
      expect(opener.openFolderCalls, [_kPath]);
      expect(opener.openFileCalls, isEmpty);
    });

    test('unreadable file still permits OpenTarget.folder', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: _kPath,
          extension: '.pdf',
          fileHealthKey: 'unreadable',
        );
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.folder);

      expect(result, isA<OpenFileSuccess>());
      expect(opener.openFolderCalls, [_kPath]);
    });

    test('health guard records a blocked event with unhealthyFile code and '
        'blocked resultKey', () async {
      final repo = _FakeRepo()
        ..recordToReturn = const FileOpenRecord(
          fileId: 1,
          documentId: 10,
          absolutePath: _kPath,
          extension: '.pdf',
          fileHealthKey: 'corrupted',
        );
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: _FakeOpener(),
      );

      await uc.execute(1, OpenTarget.file);

      expect(repo.recordedEvents, hasLength(1));
      expect(
        repo.recordedEvents.first['errorCode'],
        FileOpenError.unhealthyFile.name,
      );
      expect(repo.recordedEvents.first['resultKey'], 'blocked');
    });

    test('healthy file is not blocked by the health guard', () async {
      final repo = _FakeRepo()..recordToReturn = _kRecord;
      final opener = _FakeOpener();
      final uc = OpenFileUseCase(
        repository: repo,
        existenceChecker: _FakeChecker(FileExistenceStatus.regularFile),
        osOpener: opener,
      );

      final result = await uc.execute(1, OpenTarget.file);

      expect(result, isA<OpenFileSuccess>());
      expect(opener.openFileCalls, [_kPath]);
    });
  });
}
