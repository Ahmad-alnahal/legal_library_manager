import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Iterable<File> dartFilesIn(String path) {
    final directory = Directory(path);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }

  String normalize(String path) => path.replaceAll(r'\', '/');

  test('security domain does not import data or presentation', () {
    for (final file in dartFilesIn('lib/features/security/domain')) {
      final source = normalize(file.readAsStringSync());
      expect(
        RegExp(
          r'''import\s+['"][^'"]*features/security/data/''',
        ).hasMatch(source),
        isFalse,
        reason: '${file.path}: security domain must not import from data layer',
      );
      expect(
        RegExp(
          r'''import\s+['"][^'"]*features/security/presentation/''',
        ).hasMatch(source),
        isFalse,
        reason:
            '${file.path}: security domain must not import from presentation '
            'layer',
      );
    }
  });

  test('security data does not import presentation', () {
    for (final file in dartFilesIn('lib/features/security/data')) {
      final source = normalize(file.readAsStringSync());
      expect(
        RegExp(
          r'''import\s+['"][^'"]*features/security/presentation/''',
        ).hasMatch(source),
        isFalse,
        reason:
            '${file.path}: security data must not import from presentation '
            'layer',
      );
    }
  });

  test('security domain does not import from other features', () {
    for (final file in dartFilesIn('lib/features/security/domain')) {
      final source = normalize(file.readAsStringSync());
      expect(
        RegExp(
          r'''import\s+['"][^'"]*features/(?!security)''',
        ).hasMatch(source),
        isFalse,
        reason:
            '${file.path}: security domain must not import from other '
            'features',
      );
    }
  });

  test('security audit repository has no update or delete operations', () {
    // This guard is vacuous in M14.1 (no data repositories exist yet) and
    // becomes meaningful in M14.7 when DriftSecurityAuditRepository is added.
    // The audit log must always be append-only.
    for (final file in dartFilesIn('lib/features/security/data/repositories')) {
      final path = normalize(file.path);
      if (!path.contains('security_audit')) continue;
      final source = file.readAsStringSync();
      expect(
        RegExp(r'\bupdate\b', caseSensitive: false).hasMatch(source),
        isFalse,
        reason:
            '${file.path}: security audit repository must not have update '
            'operations',
      );
      expect(
        RegExp(r'\bdelete\b', caseSensitive: false).hasMatch(source),
        isFalse,
        reason:
            '${file.path}: security audit repository must not have delete '
            'operations',
      );
    }
  });
}
