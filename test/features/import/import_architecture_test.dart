// test/features/import/import_architecture_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards M4 layering and the copy-only source-file rule:
/// - the import domain layer must not depend on Drift or `dart:io`;
/// - the import data-layer filesystem services must not call any file/folder
///   mutation API (the app only ever reads source files).
void main() {
  Iterable<File> dartFilesIn(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }

  group('import domain purity', () {
    const String domainDir = 'lib/features/import/domain';

    test('domain does not import Drift', () {
      for (final file in dartFilesIn(domainDir)) {
        expect(
          file.readAsStringSync().contains('package:drift'),
          isFalse,
          reason: '${file.path} must not import Drift',
        );
      }
    });

    test('domain does not import dart:io', () {
      for (final file in dartFilesIn(domainDir)) {
        final content = file.readAsStringSync();
        expect(
          content.contains("import 'dart:io'") ||
              content.contains('import "dart:io"'),
          isFalse,
          reason: '${file.path} must not import dart:io',
        );
      }
    });

    test('domain does not import the Drift database barrel', () {
      for (final file in dartFilesIn(domainDir)) {
        expect(
          file.readAsStringSync().contains('core/database/app_database'),
          isFalse,
          reason: '${file.path} must not import the database',
        );
      }
    });
  });

  group('import history purity (P2.3)', () {
    const List<String> historyPresentationFiles = [
      'lib/features/import/presentation/bloc/import_history_bloc.dart',
      'lib/features/import/presentation/widgets/import_history_section.dart',
    ];

    test('import history presentation layer does not import Drift', () {
      for (final path in historyPresentationFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing $path');
        expect(
          file.readAsStringSync().contains('package:drift'),
          isFalse,
          reason: '$path must not import Drift',
        );
      }
    });

    test('get_recent_import_batches_use_case does not import Drift', () {
      const String path =
          'lib/features/import/domain/usecases/get_recent_import_batches_use_case.dart';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'missing $path');
      expect(
        file.readAsStringSync().contains('package:drift'),
        isFalse,
        reason: '$path must not import Drift',
      );
    });
  });

  group('filesystem services never mutate the filesystem', () {
    // The data-layer services that touch the filesystem directly.
    const List<String> serviceFiles = [
      'lib/features/import/data/services/windows_path_policy.dart',
      'lib/features/import/data/services/file_system_folder_validator.dart',
      'lib/features/import/data/services/file_system_pdf_scanner.dart',
      'lib/features/import/data/services/streaming_file_hasher.dart',
      'lib/features/import/data/services/conservative_pdf_health_inspector.dart',
    ];

    // Mutation APIs that must never appear in source-file handling code.
    const List<String> forbidden = [
      'writeAsBytes',
      'writeAsString',
      'deleteSync(',
      '.delete(',
      'renameSync(',
      '.rename(',
      'copySync(',
      '.copy(',
      'createSync(',
      '.create(',
      'openWrite(',
      'truncate(',
    ];

    test('no write/delete/move/create calls in filesystem services', () {
      for (final path in serviceFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing $path');
        final content = file.readAsStringSync();
        for (final token in forbidden) {
          expect(
            content.contains(token),
            isFalse,
            reason: '$path must not call "$token" on source files',
          );
        }
      }
    });
  });
}
