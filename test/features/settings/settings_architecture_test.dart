// test/features/settings/settings_architecture_test.dart
//
// Architecture guard for M10.2: Settings presentation must not cross into
// the data/infrastructure layer (Drift, database, dart:io, filesystem, process).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings architecture', () {
    List<File> dartFiles(String path) => Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList(growable: false);

    test('presentation does not import Drift or the database layer', () {
      final files = dartFiles('lib/features/settings/presentation');

      for (final file in files) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('package:drift/')),
          reason: '${file.path} must not import Drift',
        );
        expect(
          source,
          isNot(contains('core/database')),
          reason: '${file.path} must not import the database layer',
        );
      }
    });

    test("presentation does not import dart:io", () {
      final files = dartFiles('lib/features/settings/presentation');

      for (final file in files) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains("import 'dart:io'")),
          reason: '${file.path} must not import dart:io',
        );
      }
    });

    test('presentation does not contain file-mutation verbs', () {
      final files = dartFiles('lib/features/settings/presentation');
      const mutationPatterns = [
        'File(',
        '.delete(',
        '.rename(',
        '.copy(',
        '.writeAs',
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
  });
}
