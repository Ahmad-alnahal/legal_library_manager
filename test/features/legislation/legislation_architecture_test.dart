import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('legislation feature architecture', () {
    String readDir(String path) {
      final dir = Directory(path);
      if (!dir.existsSync()) return '';
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
    }

    // --- domain layer ---

    test('domain layer has no Drift imports', () {
      final source = readDir('lib/features/legislation/domain');
      expect(
        source,
        isNot(contains('package:drift/drift.dart')),
        reason: 'domain must not depend on Drift',
      );
    });

    test('domain layer has no Flutter imports', () {
      final source = readDir('lib/features/legislation/domain');
      expect(
        source,
        isNot(contains('package:flutter/')),
        reason: 'domain must not depend on Flutter',
      );
    });

    test('use cases do not directly reference AppDatabase', () {
      final source = readDir('lib/features/legislation/domain/usecases');
      expect(
        source,
        isNot(contains('AppDatabase')),
        reason: 'use cases must not reference AppDatabase',
      );
    });

    test('repository contract has no concrete persistence references', () {
      final source = File(
        'lib/features/legislation/domain/repositories/'
        'legislation_relation_repository.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('AppDatabase')));
      expect(source, isNot(contains('package:drift/')));
    });

    // --- data layer ---

    test('data layer has no Flutter imports', () {
      final source = readDir('lib/features/legislation/data');
      expect(
        source,
        isNot(contains('package:flutter/')),
        reason: 'data layer must not depend on Flutter',
      );
    });

    // --- presentation BLoC layer ---

    test('BLoC layer has no Drift imports', () {
      final source = readDir('lib/features/legislation/presentation/bloc');
      expect(
        source,
        isNot(contains('package:drift/')),
        reason: 'presentation BLoC must not depend on Drift',
      );
    });

    test('BLoC layer has no direct AppDatabase references', () {
      final source = readDir('lib/features/legislation/presentation/bloc');
      expect(
        source,
        isNot(contains('AppDatabase')),
        reason: 'presentation BLoC must not reference AppDatabase',
      );
    });

    // --- presentation widget layer ---

    test('presentation widgets have no hardcoded Arabic strings', () {
      final source = readDir('lib/features/legislation/presentation');
      expect(
        RegExp(r'[؀-ۿ]').hasMatch(source),
        isFalse,
        reason:
            'presentation layer must not contain hardcoded Arabic text; '
            'use AppLocalizations instead',
      );
    });

    test('presentation widgets use AppLocalizations for strings', () {
      final source = readDir('lib/features/legislation/presentation/widgets');
      expect(
        source,
        contains('AppLocalizations.of(context)'),
        reason: 'widgets must use AppLocalizations for user-facing strings',
      );
    });
  });
}
