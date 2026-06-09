import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('document-list domain and presentation do not depend on Drift', () {
    final files = <File>[
      ...Directory('lib/features/documents/domain')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/features/documents/presentation/bloc')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('package:drift/')),
        reason: '${file.path} must remain persistence-agnostic',
      );
      expect(
        source,
        isNot(contains('core/database')),
        reason: '${file.path} must not import the database layer',
      );
    }
  });
}
