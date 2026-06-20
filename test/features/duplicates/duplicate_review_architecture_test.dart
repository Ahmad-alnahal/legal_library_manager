// test/features/duplicates/duplicate_review_architecture_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('duplicates architecture', () {
    List<File> dartFiles(String path) => Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList(growable: false);

    test('domain and presentation bloc do not import Drift', () {
      final files = [
        ...dartFiles('lib/features/duplicates/domain'),
        ...dartFiles('lib/features/duplicates/presentation/bloc'),
      ];

      for (final file in files) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('package:drift/')),
          reason: '${file.path} must remain persistence-agnostic',
        );
        expect(
          source,
          isNot(contains('core/database')),
          reason: '${file.path} must not import the database layer',
        );
      }
    });

    test('presentation page does not import Drift or dart:io', () {
      final files = dartFiles('lib/features/duplicates/presentation/pages');

      for (final file in files) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('package:drift/')),
          reason: '${file.path} must not import Drift',
        );
        expect(
          source,
          isNot(contains("import 'dart:io'")),
          reason: '${file.path} must not import dart:io',
        );
        expect(
          source,
          isNot(contains('dart:io')),
          reason: '${file.path} must not reference dart:io',
        );
      }
    });

    test('presentation does not contain file-mutation verbs', () {
      final files = dartFiles('lib/features/duplicates/presentation');
      const mutationPatterns = [
        'File(',
        '.delete(',
        '.rename(',
        '.copy(',
        '.writeAs',
        '.create(',
        'Directory.systemTemp',
        'Process.run',
        'Process.start',
      ];

      for (final file in files) {
        final source = file.readAsStringSync();
        for (final pattern in mutationPatterns) {
          expect(
            source,
            isNot(contains(pattern)),
            reason: '${file.path} must not contain mutation verb "$pattern"',
          );
        }
      }
    });

    test('domain entities do not have mutation methods', () {
      final files = dartFiles('lib/features/duplicates/domain/entities');
      const mutationVerbs = ['void set', 'void update', 'void delete'];

      for (final file in files) {
        final source = file.readAsStringSync();
        for (final verb in mutationVerbs) {
          expect(
            source,
            isNot(contains(verb)),
            reason: '${file.path} must be read-only (no $verb)',
          );
        }
      }
    });
  });
}
