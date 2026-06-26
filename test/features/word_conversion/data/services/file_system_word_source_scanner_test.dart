// test/features/word_conversion/data/services/file_system_word_source_scanner_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/word_conversion/data/services/file_system_word_source_scanner.dart';

void main() {
  late Directory tempDir;
  late FileSystemWordSourceScanner scanner;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('word_scanner_test_');
    scanner = const FileSystemWordSourceScanner();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File createFile(String name, {String subDir = ''}) {
    final parent =
        subDir.isEmpty
              ? tempDir
              : Directory('${tempDir.path}${Platform.pathSeparator}$subDir')
          ..createSync(recursive: true);
    final file = File('${parent.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync('fake content');
    return file;
  }

  group('FileSystemWordSourceScanner – extension recognition', () {
    test('recognizes .doc files', () async {
      createFile('brief.doc');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, hasLength(1));
      expect(result.files.first.extension, '.doc');
    });

    test('rejects .docx files (not a supported source format)', () async {
      createFile('contract.docx');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, isEmpty);
    });

    test('recognizes .DOC (uppercase) case-insensitively', () async {
      createFile('brief.DOC');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, hasLength(1));
      expect(result.files.first.extension, '.doc');
    });

    test('rejects .DOCX (uppercase) even case-insensitively', () async {
      createFile('contract.DOCX');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, isEmpty);
    });

    test('does not return .pdf files', () async {
      createFile('brief.pdf');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, isEmpty);
    });

    test('does not return .txt files', () async {
      createFile('notes.txt');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, isEmpty);
    });

    test('does not return .xlsx files', () async {
      createFile('sheet.xlsx');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, isEmpty);
    });

    test('does not return files without an extension', () async {
      createFile('README');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, isEmpty);
    });
  });

  group('FileSystemWordSourceScanner – file metadata', () {
    test('returned WordSourceFile carries correct fileName', () async {
      createFile('contract.doc');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files.first.fileName, 'contract.doc');
    });

    test('returned WordSourceFile carries absolute path', () async {
      final file = createFile('brief.doc');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files.first.absolutePath, file.path);
    });

    test('returned WordSourceFile carries non-negative size', () async {
      createFile('brief.doc');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files.first.sizeBytes, greaterThanOrEqualTo(0));
    });
  });

  group('FileSystemWordSourceScanner – recursive vs non-recursive', () {
    test('finds .doc file in subdirectory when recursive=true', () async {
      createFile('nested.doc', subDir: 'subdir');

      final result = await scanner.scan(tempDir.path, recursive: true);

      expect(result.files, hasLength(1));
    });

    test(
      'does not find .doc file in subdirectory when recursive=false',
      () async {
        createFile('nested.doc', subDir: 'subdir');

        final result = await scanner.scan(tempDir.path, recursive: false);

        expect(result.files, isEmpty);
      },
    );

    test(
      'finds files at multiple nesting levels when recursive=true',
      () async {
        createFile('top.doc');
        createFile('nested.doc', subDir: 'level1');
        createFile('deep.doc', subDir: 'level1${Platform.pathSeparator}level2');

        final result = await scanner.scan(tempDir.path, recursive: true);

        expect(result.files, hasLength(3));
      },
    );
  });

  group('FileSystemWordSourceScanner – protected paths', () {
    test('skips protected subdirectory in recursive scan', () async {
      final protectedDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}WordStaging',
      )..createSync();
      createFile('staged.doc', subDir: 'WordStaging');
      createFile('real.doc');

      final result = await scanner.scan(
        tempDir.path,
        recursive: true,
        protectedPaths: [protectedDir.path],
      );

      expect(result.files, hasLength(1));
      expect(result.files.first.fileName, 'real.doc');
    });
  });

  group('FileSystemWordSourceScanner – deterministic ordering', () {
    test('results are sorted lexicographically by absolute path', () async {
      createFile('z_last.doc');
      createFile('a_first.doc');
      createFile('m_middle.doc');

      final result = await scanner.scan(tempDir.path, recursive: false);

      final names = result.files.map((f) => f.fileName).toList();
      expect(names, ['a_first.doc', 'm_middle.doc', 'z_last.doc']);
    });
  });

  group('FileSystemWordSourceScanner – mixed results', () {
    test('returns only .doc files when folder contains mixed types', () async {
      createFile('brief.doc');
      createFile('scan.pdf');
      createFile('notes.txt');
      createFile('contract.docx');
      createFile('spreadsheet.xlsx');

      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, hasLength(1));
      expect(result.files.first.extension, '.doc');
    });
  });

  group('FileSystemWordSourceScanner – empty and missing folders', () {
    test('returns empty result for empty folder', () async {
      final result = await scanner.scan(tempDir.path, recursive: false);

      expect(result.files, isEmpty);
      expect(result.failures, isEmpty);
    });

    test('returns empty result (no crash) for non-existent folder', () async {
      final result = await scanner.scan(
        '${tempDir.path}${Platform.pathSeparator}does_not_exist',
        recursive: false,
      );

      expect(result.files, isEmpty);
      expect(result.failures, isEmpty);
    });
  });
}
