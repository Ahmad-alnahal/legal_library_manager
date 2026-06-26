// test/features/word_conversion/application/check_word_conversion_readiness_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/word_conversion/application/check_word_conversion_readiness.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_capability.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/microsoft_word_probe.dart';

class _FoundProbe implements MicrosoftWordProbe {
  const _FoundProbe({required this.path, this.version});

  final String path;
  final String? version;

  @override
  Future<MicrosoftWordProbeResult> probe() async =>
      MicrosoftWordFound(executablePath: path, version: version);
}

class _NotFoundProbe implements MicrosoftWordProbe {
  const _NotFoundProbe();

  @override
  Future<MicrosoftWordProbeResult> probe() async =>
      const MicrosoftWordNotFound();
}

class _ThrowingProbe implements MicrosoftWordProbe {
  const _ThrowingProbe();

  @override
  Future<MicrosoftWordProbeResult> probe() =>
      throw Exception('simulated OS failure');
}

void main() {
  const String fakeHost = 'powershell.exe';

  group('CheckWordConversionReadiness', () {
    test(
      'returns MicrosoftWordAvailable with host and version when probe succeeds',
      () async {
        final useCase = CheckWordConversionReadiness(
          const _FoundProbe(path: fakeHost, version: '16.0'),
        );

        final result = await useCase.call();

        expect(result, isA<MicrosoftWordAvailable>());
        final available = result as MicrosoftWordAvailable;
        expect(available.executablePath, fakeHost);
        expect(available.version, '16.0');
      },
    );

    test('returns MicrosoftWordAvailable when version is null', () async {
      final useCase = CheckWordConversionReadiness(
        const _FoundProbe(path: fakeHost, version: null),
      );

      final result = await useCase.call();

      expect(result, isA<MicrosoftWordAvailable>());
      expect((result as MicrosoftWordAvailable).version, isNull);
      expect(result.executablePath, fakeHost);
    });

    test(
      'returns MicrosoftWordUnavailable when probe reports not found',
      () async {
        final useCase = CheckWordConversionReadiness(const _NotFoundProbe());

        final result = await useCase.call();

        expect(result, isA<MicrosoftWordUnavailable>());
      },
    );

    test('returns MicrosoftWordUnavailable when probe throws', () async {
      final useCase = CheckWordConversionReadiness(const _ThrowingProbe());

      final result = await useCase.call();

      expect(result, isA<MicrosoftWordUnavailable>());
    });

    test(
      'MicrosoftWordAvailable.converterKey is "microsoft_word" matching file_conversions schema',
      () {
        expect(MicrosoftWordAvailable.converterKey, 'microsoft_word');
      },
    );

    test(
      'call() always returns a WordConversionCapability, never throws',
      () async {
        for (final probe in <MicrosoftWordProbe>[
          const _FoundProbe(path: fakeHost, version: '16.0'),
          const _NotFoundProbe(),
          const _ThrowingProbe(),
        ]) {
          final useCase = CheckWordConversionReadiness(probe);
          final result = await useCase.call();
          expect(result, isA<WordConversionCapability>());
        }
      },
    );
  });
}
