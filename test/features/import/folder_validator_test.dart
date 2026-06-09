// test/features/import/folder_validator_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_folder_validator.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:path/path.dart' as p;

import 'support/import_test_support.dart';

void main() {
  const FileSystemFolderValidator validator = FileSystemFolderValidator();

  late Directory root;
  late Directory dbRoot;

  setUp(() {
    root = makeTempDir('folder');
    dbRoot = Directory(p.join(root.path, 'app_support'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  ProtectedRoots roots({String? managedLibrary}) => ProtectedRoots(
    databaseRoot: dbRoot.path,
    managedLibraryRoot: managedLibrary,
  );

  test('valid source folder passes', () async {
    final Directory source = Directory(p.join(root.path, 'sources'))
      ..createSync();
    final FolderValidationResult r = await validator.validate(
      source.path,
      protectedRoots: roots(),
    );
    expect(r.code, FolderValidationCode.valid);
    expect(r.canonicalPath, isNotNull);
  });

  test('missing folder is rejected', () async {
    final r = await validator.validate(
      p.join(root.path, 'does_not_exist'),
      protectedRoots: roots(),
    );
    expect(r.code, FolderValidationCode.doesNotExist);
  });

  test('a file path (non-directory) is rejected', () async {
    final File f = writeFile(root, 'note.txt', 'x'.codeUnits);
    final r = await validator.validate(f.path, protectedRoots: roots());
    expect(r.code, FolderValidationCode.notADirectory);
  });

  test('selecting a protected root itself is rejected', () async {
    final r = await validator.validate(dbRoot.path, protectedRoots: roots());
    expect(r.code, FolderValidationCode.isProtectedRoot);
  });

  test('a folder inside a protected root is rejected', () async {
    final Directory inside = Directory(p.join(dbRoot.path, 'nested'))
      ..createSync();
    final r = await validator.validate(inside.path, protectedRoots: roots());
    expect(r.code, FolderValidationCode.insideProtectedRoot);
  });

  test(
    'a folder containing a protected (managed library) root is rejected',
    () async {
      final Directory source = Directory(p.join(root.path, 'sources'))
        ..createSync();
      final Directory managed = Directory(p.join(source.path, 'library'))
        ..createSync();
      final r = await validator.validate(
        source.path,
        protectedRoots: roots(managedLibrary: managed.path),
      );
      expect(r.code, FolderValidationCode.containsProtectedRoot);
    },
  );

  test('a sibling sharing a string prefix is allowed', () async {
    // Protected root: <root>/data ; source: <root>/data2 (must be allowed).
    final Directory protectedData = Directory(p.join(root.path, 'data'))
      ..createSync();
    final Directory source = Directory(p.join(root.path, 'data2'))
      ..createSync();
    final r = await validator.validate(
      source.path,
      protectedRoots: ProtectedRoots(
        databaseRoot: dbRoot.path,
        managedLibraryRoot: protectedData.path,
      ),
    );
    expect(r.code, FolderValidationCode.valid);
  });

  test('case-different protected root is still detected', () async {
    final Directory source = Directory(p.join(root.path, 'Sources'))
      ..createSync();
    final r = await validator.validate(
      source.path.toUpperCase(),
      protectedRoots: ProtectedRoots(
        databaseRoot: dbRoot.path,
        managedLibraryRoot: source.path,
      ),
    );
    // Selecting (upper-cased) the same path as the managed library root.
    expect(r.code, FolderValidationCode.isProtectedRoot);
  });
}
