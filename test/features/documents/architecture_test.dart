import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards M3 layering rules: domain/application code must not depend on Drift or
/// the filesystem, and must not leak generated database rows.
void main() {
  Iterable<File> dartFilesIn(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }

  group('M3 architecture guards', () {
    const List<String> domainDirs = [
      'lib/features/documents/domain',
      'lib/features/reference/domain',
      'lib/core/validation',
      'lib/core/time',
    ];

    test('domain/application layers do not import Drift', () {
      for (final dir in domainDirs) {
        for (final file in dartFilesIn(dir)) {
          final String content = file.readAsStringSync();
          expect(
            content.contains('package:drift'),
            isFalse,
            reason: '${file.path} must not import Drift',
          );
        }
      }
    });

    test('domain/application layers introduce no filesystem APIs', () {
      for (final dir in domainDirs) {
        for (final file in dartFilesIn(dir)) {
          final String content = file.readAsStringSync();
          expect(
            content.contains("import 'dart:io'") ||
                content.contains('import "dart:io"'),
            isFalse,
            reason: '${file.path} must not import dart:io',
          );
        }
      }
    });

    test('document domain does not reference generated database row types', () {
      // Generated companions/rows live in app_database.g.dart; the domain must
      // never import the database barrel.
      for (final file in dartFilesIn('lib/features/documents/domain')) {
        final String content = file.readAsStringSync();
        expect(
          content.contains('core/database/app_database'),
          isFalse,
          reason: '${file.path} must not import the Drift database',
        );
      }
    });
  });
}
