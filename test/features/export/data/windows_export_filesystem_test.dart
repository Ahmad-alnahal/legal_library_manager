// test/features/export/data/windows_export_filesystem_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/export/data/services/windows_export_filesystem.dart';
import 'package:legal_library_manager/features/export/domain/services/export_filesystem.dart';

void main() {
  late Directory root;
  const filesystem = WindowsExportFilesystem();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('marjiy-export-fs-');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('ensureDirectoryExists', () {
    test('creates nested directories idempotently', () async {
      final target = '${root.path}\\a\\b\\c';

      final first = await filesystem.ensureDirectoryExists(target);
      expect(first, isA<ExportFilesystemSuccess>());
      expect(Directory(target).existsSync(), isTrue);

      final second = await filesystem.ensureDirectoryExists(target);
      expect(second, isA<ExportFilesystemSuccess>());
    });
  });

  group('copyFile', () {
    test('copies content to a new destination', () async {
      final source = File('${root.path}\\source.txt');
      await source.writeAsString('hello');
      final dest = '${root.path}\\dest.txt';

      final result = await filesystem.copyFile(source.path, dest);

      expect(result, isA<ExportFilesystemSuccess>());
      expect(await File(dest).readAsString(), 'hello');
    });

    test('returns failure when destination already exists', () async {
      final source = File('${root.path}\\source.txt');
      await source.writeAsString('hello');
      final dest = File('${root.path}\\dest.txt');
      await dest.writeAsString('existing');

      final result = await filesystem.copyFile(source.path, dest.path);

      expect(result, isA<ExportFilesystemFailure>());
      expect(await dest.readAsString(), 'existing');
    });
  });

  group('writeTextFile', () {
    test('writes UTF-8 content to a new file', () async {
      final target = '${root.path}\\meta.json';

      final result = await filesystem.writeTextFile(target, 'مرجعي');

      expect(result, isA<ExportFilesystemSuccess>());
      expect(await File(target).readAsString(), 'مرجعي');
    });

    test('returns failure when file already exists', () async {
      final target = File('${root.path}\\meta.json');
      await target.writeAsString('existing');

      final result = await filesystem.writeTextFile(target.path, 'new');

      expect(result, isA<ExportFilesystemFailure>());
      expect(await target.readAsString(), 'existing');
    });
  });

  group('isExistingFile', () {
    test('returns true for an existing regular file', () async {
      final file = File('${root.path}\\present.txt');
      await file.writeAsString('x');
      expect(filesystem.isExistingFile(file.path), isTrue);
    });

    test('returns false for a missing path', () {
      expect(filesystem.isExistingFile('${root.path}\\missing.txt'), isFalse);
    });

    test('returns false for a directory path', () {
      expect(filesystem.isExistingFile(root.path), isFalse);
    });
  });

  group('fileSize', () {
    test('returns the byte size of an existing file', () async {
      final file = File('${root.path}\\sized.txt');
      await file.writeAsString('12345');
      expect(await filesystem.fileSize(file.path), 5);
    });

    test('returns null for a missing file', () async {
      expect(await filesystem.fileSize('${root.path}\\missing.txt'), isNull);
    });
  });
}
