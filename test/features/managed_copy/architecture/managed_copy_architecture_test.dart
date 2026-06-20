// test/features/managed_copy/architecture/managed_copy_architecture_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards M8.1 layering and safety invariants:
///
/// - Domain and application layers have no dart:io, Drift, FFI, or process imports.
/// - The managed-copy use case has no source-mutation or shell tokens.
/// - The filesystem service exposes no delete/source-rename API.
/// - No shell command strings, cmd.exe, or PowerShell in data services.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> dartFilesIn(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }

  // ── Layer isolation: domain and application ────────────────────────────────

  group(
    'managed_copy domain and application layers contain no Drift or dart:io',
    () {
      const List<String> pureLayers = [
        'lib/features/managed_copy/domain',
        'lib/features/managed_copy/application',
      ];

      for (final dir in pureLayers) {
        test('$dir has no Drift imports', () {
          for (final file in dartFilesIn(dir)) {
            final src = read(file.path);
            expect(
              src.contains('package:drift/'),
              isFalse,
              reason: '${file.path} must not import Drift',
            );
            expect(
              src.contains('core/database'),
              isFalse,
              reason:
                  '${file.path} must not import the database layer directly',
            );
          }
        });

        test('$dir has no dart:io imports', () {
          for (final file in dartFilesIn(dir)) {
            final src = read(file.path);
            expect(
              src.contains("import 'dart:io'") ||
                  src.contains('import "dart:io"'),
              isFalse,
              reason: '${file.path} must not import dart:io',
            );
          }
        });

        test('$dir has no dart:ffi, package:ffi, or package:win32 imports', () {
          for (final file in dartFilesIn(dir)) {
            final src = read(file.path);
            expect(
              src.contains('dart:ffi'),
              isFalse,
              reason: '${file.path} must not import dart:ffi',
            );
            expect(
              src.contains('package:ffi/'),
              isFalse,
              reason: '${file.path} must not import package:ffi',
            );
            expect(
              src.contains('package:win32/'),
              isFalse,
              reason: '${file.path} must not import package:win32',
            );
          }
        });

        test('$dir has no Process usage (no shell invocation)', () {
          for (final file in dartFilesIn(dir)) {
            final src = read(file.path);
            expect(
              RegExp(r'\bProcess\s*\.').hasMatch(src),
              isFalse,
              reason: '${file.path} must not invoke Process',
            );
          }
        });
      }
    },
  );

  // ── Use case: no source-mutation or shell tokens ───────────────────────────

  group('managed_copy_use_case.dart safety', () {
    const String useCasePath =
        'lib/features/managed_copy/application/managed_copy_use_case.dart';

    late String src;
    setUpAll(() => src = read(useCasePath));

    test('does not contain cmd.exe or powershell', () {
      expect(src.toLowerCase().contains('cmd.exe'), isFalse);
      expect(src.toLowerCase().contains('powershell'), isFalse);
    });

    test('does not contain runInShell', () {
      expect(src.contains('runInShell'), isFalse);
    });

    test('does not contain .delete( or .deleteSync(', () {
      expect(src.contains('.delete('), isFalse);
      expect(src.contains('.deleteSync('), isFalse);
    });

    test('does not rename or overwrite source files', () {
      // rename/renameSync should never appear in the use case; only in the
      // filesystem service implementation.
      expect(src.contains('.rename('), isFalse);
      expect(src.contains('.renameSync('), isFalse);
    });

    test('does not write or overwrite source paths', () {
      expect(src.contains('.writeAs'), isFalse);
      expect(src.contains('.openWrite('), isFalse);
    });
  });

  // ── Filesystem service: no bulk or directory deletion API ────────────────
  // deleteFile is intentionally allowed on the interface (used only to remove
  // a conflicting managed-path file after a DB backup). Directory deletion and
  // source-path removal APIs are still forbidden.

  group(
    'managed_library_filesystem.dart interface has no directory-delete API',
    () {
      const String fsPath =
          'lib/features/managed_copy/domain/services/managed_library_filesystem.dart';

      late String src;
      setUpAll(() => src = read(fsPath));

      test('interface has no deleteDirectory or removeFile method', () {
        expect(src.contains('deleteDirectory'), isFalse);
        expect(src.contains('removeFile'), isFalse);
      });
    },
  );

  // ── Windows filesystem service: safe copy/rename only ─────────────────────

  group('windows_managed_library_filesystem.dart safety', () {
    const String implPath =
        'lib/features/managed_copy/data/services/windows_managed_library_filesystem.dart';

    late String src;
    setUpAll(() => src = read(implPath));

    test('does not use cmd.exe or powershell', () {
      expect(src.toLowerCase().contains('cmd.exe'), isFalse);
      expect(src.toLowerCase().contains('powershell'), isFalse);
    });

    test('does not use runInShell: true', () {
      expect(src.contains('runInShell: true'), isFalse);
    });

    test(
      'does not contain .delete( on source paths (no deleteSync on arbitrary paths)',
      () {
        // The service must not expose bulk/arbitrary delete.
        // Any .deleteSync usage must only target app-owned temp files;
        // as a policy guard, we verify there is no .deleteSync call at all in
        // the filesystem service (cleanup of temp files is M11 reconciliation).
        expect(src.contains('.deleteSync('), isFalse);
      },
    );
  });

  // ── SQLite backup service: VACUUM INTO used, no naive file copy ────────────

  group('sqlite_database_backup_service.dart safety', () {
    const String backupPath =
        'lib/features/managed_copy/data/services/sqlite_database_backup_service.dart';

    late String src;
    setUpAll(() => src = read(backupPath));

    test('uses VACUUM INTO for backup', () {
      expect(
        src.contains('VACUUM INTO'),
        isTrue,
        reason: 'Must use VACUUM INTO for a consistent SQLite backup',
      );
    });

    test('does not use naive File.copy on the live database file', () {
      // Copying the live .sqlite file directly is unsafe with WAL mode.
      // The service must use VACUUM INTO, not File.copy.
      // Guard: no ".copy(" call that could naively copy the database.
      // (The verify helper reads only the backup file — that is allowed.)
      final linesWithCopy = src
          .split('\n')
          .where((l) => l.contains('.copy(') && !l.trimLeft().startsWith('//'))
          .toList();
      expect(
        linesWithCopy,
        isEmpty,
        reason: 'Must not use File.copy on the live database',
      );
    });

    test('validates path safety before embedding in SQL', () {
      expect(
        src.contains("contains(\"'\")"),
        isTrue,
        reason: 'Must guard against single quotes in the backup path',
      );
    });
  });

  // ── Drift repository: no source file mutations ────────────────────────────

  group('drift_managed_copy_repository.dart does not mutate source records', () {
    const String repoPath =
        'lib/features/managed_copy/data/repositories/drift_managed_copy_repository.dart';

    late String src;
    setUpAll(() => src = read(repoPath));

    test('does not delete from document_files or documents', () {
      expect(src.contains('_db.delete('), isFalse);
      expect(src.contains('_db.delete(_db.documentFiles'), isFalse);
      expect(src.contains('_db.delete(_db.documents'), isFalse);
    });

    test(
      'does not update file_role_key or is_read_only_source of source rows',
      () {
        // Source rows must never have their role or read-only flag mutated.
        // The only updates allowed are on the document row (workflow) and
        // inserting new managed_copy rows.
        expect(
          src.contains("fileRoleKey: Value('source_original')") &&
              src.contains('update'),
          isFalse,
          reason: 'Must not update source_original file role',
        );
      },
    );
  });

  // ── Correction 2: no raw OS error messages in filesystem service ──────────

  group(
    'windows_managed_library_filesystem.dart has no raw OS errors (correction 6)',
    () {
      const String implPath =
          'lib/features/managed_copy/data/services/windows_managed_library_filesystem.dart';

      late String src;
      setUpAll(() => src = read(implPath));

      test('does not use osError', () {
        expect(
          src.contains('osError'),
          isFalse,
          reason: 'Must never embed raw OS error messages in results',
        );
      });

      test('creates temporary destinations exclusively', () {
        expect(
          src.contains('create(exclusive: true)'),
          isTrue,
          reason:
              'Temporary managed-copy creation must atomically refuse overwrite races',
        );
        expect(
          src.contains('.copy(destPath)'),
          isFalse,
          reason:
              'File.copy after an exists check can overwrite a raced destination',
        );
      });

      test(
        'recovery inspection is non-recursive and does not follow links',
        () {
          expect(src.contains('listSync(followLinks: false)'), isTrue);
          expect(src.contains('recursive: true'), isFalse);
          expect(src.contains('.deleteSync('), isFalse);
        },
      );
    },
  );

  // ── Correction 5: backup service uses PRAGMA quick_check ─────────────────

  group(
    'sqlite_database_backup_service.dart uses PRAGMA quick_check (correction 5)',
    () {
      const String backupSvcPath =
          'lib/features/managed_copy/data/services/sqlite_database_backup_service.dart';

      late String src;
      setUpAll(() => src = read(backupSvcPath));

      test('contains PRAGMA quick_check', () {
        expect(
          src.contains('PRAGMA quick_check'),
          isTrue,
          reason: 'Backup verification must run PRAGMA quick_check',
        );
      });
    },
  );

  // ── Correction 2: PathCanonicalizer and OperationIdGenerator
  //    implementations are in data layer only ─────────────────────────────────

  group(
    'PathCanonicalizer / OperationIdGenerator: impls are in data layer only (correction 2/3)',
    () {
      test('no concrete canonicalizer class in domain layer', () {
        for (final file in dartFilesIn('lib/features/managed_copy/domain')) {
          final src = read(file.path);
          expect(
            src.contains('implements PathCanonicalizer') ||
                src.contains('extends PathCanonicalizer'),
            isFalse,
            reason: '${file.path} must not contain PathCanonicalizer impl',
          );
        }
      });

      test('no concrete id generator class in domain layer', () {
        for (final file in dartFilesIn('lib/features/managed_copy/domain')) {
          final src = read(file.path);
          expect(
            src.contains('implements OperationIdGenerator') ||
                src.contains('extends OperationIdGenerator'),
            isFalse,
            reason: '${file.path} must not contain OperationIdGenerator impl',
          );
        }
      });

      test('no concrete canonicalizer class in application layer', () {
        for (final file in dartFilesIn(
          'lib/features/managed_copy/application',
        )) {
          final src = read(file.path);
          expect(
            src.contains('implements PathCanonicalizer') ||
                src.contains('extends PathCanonicalizer'),
            isFalse,
            reason: '${file.path} must not contain PathCanonicalizer impl',
          );
        }
      });

      test('no concrete id generator class in application layer', () {
        for (final file in dartFilesIn(
          'lib/features/managed_copy/application',
        )) {
          final src = read(file.path);
          expect(
            src.contains('implements OperationIdGenerator') ||
                src.contains('extends OperationIdGenerator'),
            isFalse,
            reason: '${file.path} must not contain OperationIdGenerator impl',
          );
        }
      });
    },
  );

  group('M8.2 presentation remains behind safe boundaries', () {
    test(
      'managed_copy presentation has no filesystem, Drift, or file picker',
      () {
        for (final file in dartFilesIn(
          'lib/features/managed_copy/presentation',
        )) {
          final src = read(file.path);
          for (final forbidden in [
            "import 'dart:io'",
            'package:drift/',
            'package:file_picker/',
            'File(',
            'Directory(',
            'Process.',
          ]) {
            expect(
              src.contains(forbidden),
              isFalse,
              reason: '${file.path} must not contain $forbidden',
            );
          }
        }
      },
    );

    test('settings page does not access filesystem or database directly', () {
      final src = read(
        'lib/features/settings/presentation/pages/settings_page.dart',
      );
      expect(src.contains("import 'dart:io'"), isFalse);
      expect(src.contains('package:drift/'), isFalse);
      expect(src.contains('package:file_picker/'), isFalse);
      expect(src.contains('package:path_provider/'), isFalse);
      expect(src.contains('AppDatabase'), isFalse);
      // Must not import any managed_copy data-layer implementation (filesystem,
      // canonicalizer, resolver, repository). Presentation depends only on the
      // application/domain boundaries.
      expect(
        src.contains('managed_copy/data/'),
        isFalse,
        reason: 'Settings must not import managed_copy data-layer code',
      );
    });
  });

  // ── M8.4: automatic copy-root setup never moves, deletes, or copies files ──

  group('M8.4 initialize_copy_roots.dart prohibits file mutation', () {
    const String initPath =
        'lib/features/managed_copy/application/initialize_copy_roots.dart';

    late String src;
    setUpAll(() => src = read(initPath));

    test('contains no delete/rename/move tokens', () {
      for (final token in [
        '.delete(',
        '.deleteSync(',
        '.rename(',
        '.renameSync(',
      ]) {
        expect(
          src.contains(token),
          isFalse,
          reason: 'initialize_copy_roots.dart must not contain $token',
        );
      }
    });

    test('does not copy or finalize files', () {
      expect(src.contains('.copy('), isFalse);
      expect(
        src.contains('copyFile('),
        isFalse,
        reason: 'must not copy managed/source files during setup',
      );
      expect(
        src.contains('finalizeFile('),
        isFalse,
        reason: 'must not finalize/rename files during setup',
      );
    });

    test('touches the filesystem only via safe directory boundaries', () {
      // Directory creation/existence are the only allowed filesystem calls;
      // any file-level boundary call would risk mutating managed content.
      for (final forbidden in [
        'fileSize(',
        'findRecoveryArtifacts(',
        'isExistingFile(',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'initialize_copy_roots.dart must not call $forbidden',
        );
      }
    });
  });

  // ── M8.5: explicit missing-folder repair never moves/copies/deletes files ──

  group('M8.5 repair_copy_root.dart prohibits file mutation', () {
    const String repairPath =
        'lib/features/managed_copy/application/repair_copy_root.dart';

    late String src;
    setUpAll(() => src = read(repairPath));

    test('contains no delete/rename/move tokens', () {
      for (final token in [
        '.delete(',
        '.deleteSync(',
        '.rename(',
        '.renameSync(',
      ]) {
        expect(
          src.contains(token),
          isFalse,
          reason: 'repair_copy_root.dart must not contain $token',
        );
      }
    });

    test('does not copy or finalize files', () {
      expect(src.contains('.copy('), isFalse);
      expect(
        src.contains('copyFile('),
        isFalse,
        reason: 'must not copy managed/source files during repair',
      );
      expect(
        src.contains('finalizeFile('),
        isFalse,
        reason: 'must not finalize/rename files during repair',
      );
    });

    test('touches the filesystem only via safe directory boundaries', () {
      for (final forbidden in [
        'fileSize(',
        'findRecoveryArtifacts(',
        'isExistingFile(',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'repair_copy_root.dart must not call $forbidden',
        );
      }
    });

    test('has no Drift or dart:io imports', () {
      expect(src.contains('package:drift/'), isFalse);
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });
  });

  group('M8.4 documents resolver respects Clean Architecture layering', () {
    test('domain abstraction has no path_provider or dart:io import', () {
      final src = read(
        'lib/features/managed_copy/domain/services/documents_directory_resolver.dart',
      );
      expect(src.contains('package:path_provider/'), isFalse);
      expect(src.contains("import 'dart:io'"), isFalse);
    });

    test('path_provider resolver implementation lives in the data layer', () {
      final implFile = File(
        'lib/features/managed_copy/data/services/path_provider_documents_directory_resolver.dart',
      );
      expect(implFile.existsSync(), isTrue);
      final src = implFile.readAsStringSync();
      expect(src.contains('package:path_provider/'), isTrue);
      expect(src.contains('implements DocumentsDirectoryResolver'), isTrue);
    });
  });
}
