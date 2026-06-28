// test/features/related_files/related_files_architecture_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards P2.4 layering:
/// - domain layer (entities + repository) must not import Drift or Flutter;
/// - application layer must not import Drift or Flutter;
/// - data layer must not import Flutter;
/// - no presentation directory must exist (P2.4 has no UI).
void main() {
  Iterable<File> dartFilesIn(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }

  bool containsDrift(File f) => f.readAsStringSync().contains('package:drift');

  bool containsFlutter(File f) =>
      f.readAsStringSync().contains('package:flutter');

  group('related_files domain purity', () {
    const String domainDir = 'lib/features/related_files/domain';

    test('domain entities do not import Drift', () {
      for (final file in dartFilesIn('$domainDir/entities')) {
        expect(
          containsDrift(file),
          isFalse,
          reason: '${file.path} must not import Drift',
        );
      }
    });

    test('domain repository contract does not import Drift', () {
      for (final file in dartFilesIn('$domainDir/repositories')) {
        expect(
          containsDrift(file),
          isFalse,
          reason: '${file.path} must not import Drift',
        );
      }
    });

    test('domain layer does not import Flutter', () {
      for (final file in dartFilesIn(domainDir)) {
        expect(
          containsFlutter(file),
          isFalse,
          reason: '${file.path} must not import Flutter',
        );
      }
    });
  });

  group('related_files application purity', () {
    const String appDir = 'lib/features/related_files/application';

    test('application layer does not import Drift', () {
      for (final file in dartFilesIn(appDir)) {
        expect(
          containsDrift(file),
          isFalse,
          reason: '${file.path} must not import Drift',
        );
      }
    });

    test('application layer does not import Flutter', () {
      for (final file in dartFilesIn(appDir)) {
        expect(
          containsFlutter(file),
          isFalse,
          reason: '${file.path} must not import Flutter',
        );
      }
    });
  });

  group('related_files data layer', () {
    test('data repository does not import Flutter', () {
      for (final file in dartFilesIn('lib/features/related_files/data')) {
        expect(
          containsFlutter(file),
          isFalse,
          reason: '${file.path} must not import Flutter',
        );
      }
    });
  });

  group('P2.4 presentation guard', () {
    test('no presentation directory exists for related_files in P2.4', () {
      final dir = Directory('lib/features/related_files/presentation');
      expect(
        dir.existsSync(),
        isFalse,
        reason:
            'lib/features/related_files/presentation/ must not exist in P2.4 '
            '(review UI is deferred to P2.5)',
      );
    });
  });
}
