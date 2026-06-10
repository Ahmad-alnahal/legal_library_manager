import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards review-workflow layering and safety: document domain/application code
/// stays persistence/filesystem agnostic, and no review code introduces file
/// copy/move/delete/open or OS-integration behavior.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> dartFilesIn(String path) {
    final directory = Directory(path);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
  }

  final domainAndApplicationFiles = [
    ...dartFilesIn('lib/features/documents/domain'),
    ...dartFilesIn('lib/features/documents/application'),
  ];
  final reviewFiles = [
    ...dartFilesIn('lib/features/documents/domain'),
    ...dartFilesIn('lib/features/documents/presentation'),
    File(
      'lib/features/documents/data/repositories/'
      'drift_review_queue_repository.dart',
    ),
  ];

  test('document domain/application do not depend on Drift or dart:io', () {
    for (final file in domainAndApplicationFiles) {
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
      expect(
        source.contains("import 'dart:io'"),
        isFalse,
        reason: '${file.path} must not import dart:io',
      );
    }
  });

  test('no review code introduces file copy/move/delete/open behavior', () {
    // Filesystem/OS surfaces that would break the copy-only, no-open guarantees.
    const forbidden = <String>[
      'dart:io',
      'File(',
      'Directory(',
      '.copy(',
      '.copySync(',
      '.rename(',
      '.renameSync(',
      '.delete(',
      '.deleteSync(',
      'Process.run',
      'Process.start',
      'launchUrl',
      'url_launcher',
      'OpenFilex',
      'open_file',
    ];
    for (final file in reviewFiles) {
      final source = read(file.path);
      for (final token in forbidden) {
        final bool found = switch (token) {
          'File(' => RegExp(r'\bFile\s*\(').hasMatch(source),
          'Directory(' => RegExp(r'\bDirectory\s*\(').hasMatch(source),
          _ => source.contains(token),
        };
        expect(
          found,
          isFalse,
          reason:
              '${file.path} must not contain "$token" '
              '(no file/OS side effects)',
        );
      }
    }
  });

  test('review-queue repository is read-only (no write statements)', () {
    final source = read(
      'lib/features/documents/data/repositories/drift_review_queue_repository.dart',
    );
    for (final write in const ['_db.update', '_db.delete', '_db.into']) {
      expect(
        source.contains(write),
        isFalse,
        reason: 'the review queue repository must only read',
      );
    }
  });
}
