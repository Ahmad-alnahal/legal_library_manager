// test/features/word_conversion/data/services/windows_microsoft_word_probe_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/word_conversion/data/services/windows_microsoft_word_probe.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/microsoft_word_probe.dart';

void main() {
  group('WindowsMicrosoftWordProbe', () {
    test('returns found when version probe succeeds', () async {
      final probe = WindowsMicrosoftWordProbe(
        hostExecutable: 'powershell.exe',
        versionProbe: (_) async => '16.0',
      );

      final result = await probe.probe();

      expect(result, isA<MicrosoftWordFound>());
      final found = result as MicrosoftWordFound;
      expect(found.executablePath, 'powershell.exe');
      expect(found.version, '16.0');
    });

    test('returns not found when version probe returns null', () async {
      final probe = WindowsMicrosoftWordProbe(versionProbe: (_) async => null);

      final result = await probe.probe();

      expect(result, isA<MicrosoftWordNotFound>());
    });

    test('returns not found when version probe throws', () async {
      final probe = WindowsMicrosoftWordProbe(
        versionProbe: (_) => throw Exception('COM unavailable'),
      );

      final result = await probe.probe();

      expect(result, isA<MicrosoftWordNotFound>());
    });
  });
}
