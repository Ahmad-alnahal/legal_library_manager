import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards M6.1 layering and safety: the review workflow's domain/presentation
/// code stays persistence/filesystem agnostic, and nothing in the new review
/// code introduces file copy/move/delete/open or OS-integration behavior.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const List<String> domainAndPresentationFiles = [
    'lib/features/documents/domain/entities/review_queue_query.dart',
    'lib/features/documents/domain/entities/review_queue_item.dart',
    'lib/features/documents/domain/repositories/review_queue_repository.dart',
    'lib/features/documents/domain/usecases/load_document_aggregate.dart',
    'lib/features/documents/domain/usecases/return_to_in_progress.dart',
    'lib/features/documents/presentation/bloc/review_bloc.dart',
    'lib/features/documents/presentation/bloc/review_event.dart',
    'lib/features/documents/presentation/bloc/review_state.dart',
  ];

  // Includes the read-only data repository and the modified metadata repo.
  const List<String> allReviewFiles = [
    ...domainAndPresentationFiles,
    'lib/features/documents/data/repositories/drift_review_queue_repository.dart',
  ];

  test('review domain/presentation do not depend on Drift or dart:io', () {
    for (final path in domainAndPresentationFiles) {
      final source = read(path);
      expect(
        source.contains('package:drift/'),
        isFalse,
        reason: '$path must remain persistence-agnostic',
      );
      expect(
        source.contains('core/database'),
        isFalse,
        reason: '$path must not import the database layer',
      );
      expect(
        source.contains("import 'dart:io'"),
        isFalse,
        reason: '$path must not import dart:io',
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
    for (final path in allReviewFiles) {
      final source = read(path);
      for (final token in forbidden) {
        expect(
          source.contains(token),
          isFalse,
          reason: '$path must not contain "$token" (no file/OS side effects)',
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
