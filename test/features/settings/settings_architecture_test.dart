// test/features/settings/settings_architecture_test.dart
//
// Architecture guards for M10.2 and M11.1: Settings presentation must not
// cross into the data/infrastructure layer (Drift, database, dart:io,
// filesystem, process, or Windows APIs).

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

    test('presentation does not import dart:io', () {
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

    // M11.1: ManualBackupBloc (presentation) must not import
    // Drift, dart:io, or filesystem/process APIs.
    test('manual backup BLoC does not import Drift or dart:io', () {
      final files = dartFiles(
        'lib/features/managed_copy/presentation/bloc',
      ).where((f) => f.path.contains('manual_backup_bloc'));

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
          isNot(contains('dart:ffi')),
          reason: '${file.path} must not import dart:ffi',
        );
      }
    });

    // M11.1: CreateManualBackup (application) must not import
    // Drift, dart:io, dart:ffi, or Windows APIs.
    test(
      'create_manual_backup application use case has no infrastructure imports',
      () {
        const path =
            'lib/features/managed_copy/application/create_manual_backup.dart';
        final source = File(path).readAsStringSync();

        expect(
          source,
          isNot(contains('package:drift/')),
          reason: 'create_manual_backup must not import Drift',
        );
        expect(
          source,
          isNot(contains("import 'dart:io'")),
          reason: 'create_manual_backup must not import dart:io',
        );
        expect(
          source,
          isNot(contains('dart:ffi')),
          reason: 'create_manual_backup must not import FFI',
        );
        expect(
          source,
          isNot(contains('Process.')),
          reason: 'create_manual_backup must not invoke processes',
        );
      },
    );

    // Source-file safety: backup application layer must not contain source-mutation verbs.
    test('backup flow does not contain source-file mutation verbs', () {
      const backupFiles = [
        'lib/features/managed_copy/application/create_manual_backup.dart',
        'lib/features/managed_copy/domain/entities/manual_backup_result.dart',
        'lib/features/managed_copy/presentation/bloc/manual_backup_bloc.dart',
      ];
      const mutationVerbs = [
        '.delete(',
        '.rename(',
        '.moveSync',
        '.deleteSync',
        '.writeAs',
        'source_original',
      ];
      for (final path in backupFiles) {
        final source = File(path).readAsStringSync();
        for (final verb in mutationVerbs) {
          expect(
            source,
            isNot(contains(verb)),
            reason: '$path must not contain source-mutation verb "$verb"',
          );
        }
      }
    });
  });
}
