import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Iterable<File> dartFilesIn(String path) {
    final directory = Directory(path);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
  }

  test('core outside the composition root does not depend on features', () {
    for (final file in dartFilesIn('lib/core')) {
      final normalized = file.path.replaceAll(r'\', '/');
      if (normalized.contains('/core/di/')) continue;

      final source = file.readAsStringSync();
      expect(
        RegExp(
          r'''import\s+['"][^'"]*features/''',
        ).hasMatch(source.replaceAll(r'\', '/')),
        isFalse,
        reason:
            '${file.path} must remain reusable; only core/di may compose '
            'feature implementations',
      );
    }
  });
}
