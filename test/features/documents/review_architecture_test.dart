import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards review-workflow and safe-open layering and safety.
///
/// M7.2 intentionally permits opening source files/folders, but only through
/// the approved `file_open` feature: a presentation controller drives the M7.1
/// use case, and only the `file_open` data service touches the OS. These guards
/// prove the document/review presentation never imports OS/process/Win32/FFI
/// APIs, never mutates files, never calls the use case directly, and that the
/// safe-open UI boundary cannot receive an arbitrary path.
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

  bool containsToken(String source, String token) => switch (token) {
    'File(' => RegExp(r'\bFile\s*\(').hasMatch(source),
    'Directory(' => RegExp(r'\bDirectory\s*\(').hasMatch(source),
    _ => source.contains(token),
  };

  // Filesystem/OS/process surfaces that would break copy-only, no-shell, and
  // no-direct-OS-in-presentation guarantees.
  const forbiddenOsTokens = <String>[
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
    'dart:ffi',
    'package:ffi',
    'package:win32',
    'ShellExecute',
    'launchUrl',
    'url_launcher',
    'OpenFilex',
  ];

  final domainAndApplicationFiles = [
    ...dartFilesIn('lib/features/documents/domain'),
    ...dartFilesIn('lib/features/documents/application'),
  ];

  // Presentation that must never touch the OS directly: the document/review UI
  // plus the safe-open controller and widgets (the controller delegates to the
  // use case; it must not itself reach the OS).
  final presentationFiles = [
    ...dartFilesIn('lib/features/documents/presentation'),
    ...dartFilesIn('lib/features/file_open/presentation'),
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

  test('document/review and safe-open presentation contain no OS/process/FFI '
      'behavior or file mutation', () {
    for (final file in presentationFiles) {
      final source = read(file.path);
      expect(
        source.contains('package:drift/'),
        isFalse,
        reason: '${file.path} must not import Drift',
      );
      for (final token in forbiddenOsTokens) {
        expect(
          containsToken(source, token),
          isFalse,
          reason:
              '${file.path} must not contain "$token" '
              '(no OS/process/FFI or file side effects in presentation)',
        );
      }
    }
  });

  test(
    'document/review presentation drives opening only through the controller, '
    'never the use case directly',
    () {
      for (final file in dartFilesIn('lib/features/documents/presentation')) {
        final source = read(file.path);
        expect(
          source.contains('OpenFileUseCase'),
          isFalse,
          reason:
              '${file.path} must use FileOpenBloc, not OpenFileUseCase directly',
        );
        expect(
          source.contains('open_file_use_case'),
          isFalse,
          reason: '${file.path} must not import the use case directly',
        );
      }
    },
  );

  test('only the file_open data service performs OS/Win32/process work', () {
    // Positive proof the OS boundary lives where expected.
    final invoker = read(
      'lib/features/file_open/data/services/windows_os_file_opener.dart',
    );
    expect(
      invoker.contains('ShellExecuteEx'),
      isTrue,
      reason: 'the OS boundary must use ShellExecuteEx',
    );

    // No other file_open layer (domain/application/presentation) touches the OS.
    final nonServiceFiles = [
      ...dartFilesIn('lib/features/file_open/domain'),
      ...dartFilesIn('lib/features/file_open/application'),
      ...dartFilesIn('lib/features/file_open/presentation'),
    ];
    for (final file in nonServiceFiles) {
      final source = read(file.path);
      for (final token in const [
        'Process.run',
        'Process.start',
        'dart:ffi',
        'package:ffi',
        'package:win32',
        'ShellExecute',
      ]) {
        expect(
          source.contains(token),
          isFalse,
          reason: '${file.path} must not contain OS surface "$token"',
        );
      }
    }
  });

  test(
    'the safe-open UI boundary accepts only a file id and target, never a path',
    () {
      final event = read(
        'lib/features/file_open/presentation/bloc/file_open_event.dart',
      );
      // Carries the registered id and the target.
      expect(event.contains('fileId'), isTrue);
      expect(event.contains('OpenTarget'), isTrue);
      // No path of any kind can enter through the request event.
      expect(
        event.contains('absolutePath'),
        isFalse,
        reason: 'requests must not carry a path',
      );
      expect(
        RegExp(r'String\s+\w*[Pp]ath').hasMatch(event),
        isFalse,
        reason: 'requests must not carry any path string',
      );

      // The use case itself only accepts an int id + target (no path param).
      final useCase = read(
        'lib/features/file_open/application/open_file_use_case.dart',
      );
      expect(
        RegExp(r'execute\(\s*int\s+fileId').hasMatch(useCase),
        isTrue,
        reason: 'the use case must take a database file id, not a path',
      );
    },
  );

  test('presentation never compares health strings directly — must use '
      'canOpenFileDirectly()', () {
    final filesToCheck = [
      ...dartFilesIn('lib/features/documents/presentation'),
      ...dartFilesIn('lib/features/file_open/presentation'),
    ];
    for (final file in filesToCheck) {
      final source = read(file.path);
      expect(
        source.contains("== 'healthy'") || source.contains("!= 'healthy'"),
        isFalse,
        reason:
            '${file.path} must call canOpenFileDirectly() rather than '
            "comparing health strings with == 'healthy' or != 'healthy'",
      );
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
