import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'category management presentation has no persistence or filesystem APIs',
    () {
      final root = Directory('lib/features/categories/presentation');
      final source = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(source, isNot(contains('package:drift/drift.dart')));
      expect(source, isNot(contains("import 'dart:io'")));
      expect(source, isNot(contains('delete(')));
      expect(source, isNot(contains('Remove-Item')));
    },
  );

  test(
    'category-management contract exposes no permanent delete operation',
    () {
      final source = File(
        'lib/features/categories/domain/repositories/'
        'category_management_repository.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('deleteMainCategory')));
      expect(source, isNot(contains('deleteSubCategory')));
    },
  );
}
