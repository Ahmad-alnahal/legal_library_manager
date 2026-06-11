// test/features/file_open/file_open_architecture_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards M7.1 layering and safety rules:
/// - Domain and application layers remain persistence/filesystem agnostic.
/// - Windows OS invoker contains no shell command strings, cmd.exe,
///   PowerShell, runInShell: true, or file-mutation operations.
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

  // -------------------------------------------------------------------------
  // Layer isolation
  // -------------------------------------------------------------------------

  group(
    'file_open domain and application layers do not import Drift or dart:io',
    () {
      const List<String> pureLayerDirs = [
        'lib/features/file_open/domain',
        'lib/features/file_open/application',
      ];

      for (final dir in pureLayerDirs) {
        test('$dir contains no Drift imports', () {
          for (final file in dartFilesIn(dir)) {
            final source = read(file.path);
            expect(
              source.contains('package:drift/'),
              isFalse,
              reason: '${file.path} must remain persistence-agnostic',
            );
            expect(
              source.contains('core/database'),
              isFalse,
              reason: '${file.path} must not import the database layer',
            );
          }
        });

        test('$dir contains no dart:io imports', () {
          for (final file in dartFilesIn(dir)) {
            final source = read(file.path);
            expect(
              source.contains("import 'dart:io'") ||
                  source.contains('import "dart:io"'),
              isFalse,
              reason: '${file.path} must not import dart:io',
            );
          }
        });
      }
    },
  );

  // -------------------------------------------------------------------------
  // Windows OS invoker safety
  // -------------------------------------------------------------------------

  group('windows_os_file_opener.dart contains no unsafe shell patterns', () {
    const String invokerPath =
        'lib/features/file_open/data/services/windows_os_file_opener.dart';

    late String source;

    setUpAll(() {
      source = read(invokerPath);
    });

    test('does not use cmd.exe', () {
      expect(
        source.toLowerCase().contains('cmd.exe'),
        isFalse,
        reason: 'No cmd.exe usage allowed',
      );
    });

    test('does not use PowerShell', () {
      expect(
        source.toLowerCase().contains('powershell'),
        isFalse,
        reason: 'No PowerShell usage allowed',
      );
    });

    test('does not use shell start command', () {
      // Checks for 'start' or "start" as a Windows shell built-in invocation
      // pattern; does not match Dart identifiers like Process.start.
      final hasShellStart =
          source.contains("'start'") || source.contains('"start"');
      expect(
        hasShellStart,
        isFalse,
        reason: 'No shell "start" command allowed',
      );
    });

    test('does not set runInShell to true', () {
      expect(
        source.contains('runInShell: true'),
        isFalse,
        reason: 'runInShell must never be true',
      );
    });

    test('does not contain .copy( or .copySync(', () {
      expect(source.contains('.copy('), isFalse);
      expect(source.contains('.copySync('), isFalse);
    });

    test('does not contain .move( or rename', () {
      expect(source.contains('.rename('), isFalse);
      expect(source.contains('.renameSync('), isFalse);
    });

    test('does not contain .delete( or .deleteSync(', () {
      expect(source.contains('.delete('), isFalse);
      expect(source.contains('.deleteSync('), isFalse);
    });

    test('passes executable and arguments separately to Process.start', () {
      // Confirm Process.start is used for the folder-reveal path (explorer.exe
      // /select,<path>). File opens use ShellExecuteEx instead.
      final bool usesProcessStart = source.contains('Process.start');
      expect(
        usesProcessStart,
        isTrue,
        reason: 'Windows invoker must use Process.start for folder reveal',
      );
    });

    test('uses ShellExecuteEx to open files', () {
      expect(
        source.contains('ShellExecuteEx'),
        isTrue,
        reason:
            'File opens must use ShellExecuteEx for accurate success/failure reporting',
      );
    });

    test('suppresses system error dialogs via SEE_MASK_FLAG_NO_UI', () {
      // 0x00000400 is SEE_MASK_FLAG_NO_UI; errors are returned as codes.
      expect(
        source.contains('0x00000400') || source.contains('SEE_MASK_FLAG_NO_UI'),
        isTrue,
        reason: 'ShellExecuteEx must suppress system error dialogs',
      );
    });

    test('does not request elevation via runas verb', () {
      expect(
        source.contains("'runas'") || source.contains('"runas"'),
        isFalse,
        reason: 'No elevation via runas verb is permitted',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Application layer: no file mutation tokens
  // -------------------------------------------------------------------------

  group(
    'open_file_use_case.dart contains no file mutation or shell tokens',
    () {
      const String useCasePath =
          'lib/features/file_open/application/open_file_use_case.dart';

      late String source;

      setUpAll(() {
        source = read(useCasePath);
      });

      test('does not contain cmd.exe or powershell', () {
        expect(source.toLowerCase().contains('cmd.exe'), isFalse);
        expect(source.toLowerCase().contains('powershell'), isFalse);
      });

      test('does not contain runInShell', () {
        expect(source.contains('runInShell'), isFalse);
      });

      test('does not contain .copy( .rename( or .delete(', () {
        expect(source.contains('.copy('), isFalse);
        expect(source.contains('.rename('), isFalse);
        expect(source.contains('.delete('), isFalse);
      });
    },
  );

  // -------------------------------------------------------------------------
  // Drift repository: read + append only, no document/file mutations
  // -------------------------------------------------------------------------

  group('drift_file_open_repository.dart is read + append only', () {
    const String repoPath =
        'lib/features/file_open/data/repositories/drift_file_open_repository.dart';

    late String source;

    setUpAll(() {
      source = read(repoPath);
    });

    test('does not contain _db.update, _db.delete, or _db.customUpdate', () {
      expect(source.contains('_db.update'), isFalse);
      expect(source.contains('_db.delete'), isFalse);
      expect(source.contains('_db.customUpdate'), isFalse);
    });

    test('does not write to documents or document_files tables', () {
      // Writes to these tables would modify workflow state or source records.
      expect(
        source.contains('db.documents)') && source.contains('.insert('),
        isFalse,
        reason: 'Must not insert into documents',
      );
      expect(
        source.contains('db.documentFiles)') && source.contains('.insert('),
        isFalse,
        reason: 'Must not insert into document_files',
      );
    });
  });
}
