// lib/features/word_conversion/application/check_word_conversion_readiness.dart

import '../domain/entities/word_conversion_capability.dart';
import '../domain/services/microsoft_word_probe.dart';

/// Checks whether the system is ready to convert Word documents to PDF.
///
/// P1.1 scope: capability detection only. No file is converted and no Word
/// import UI is activated. Future P1.x slices will build on this foundation.
///
/// The use case delegates all OS interaction to the injectable [MicrosoftWordProbe]
/// and returns a structured [WordConversionCapability] — never a raw exception.
class CheckWordConversionReadiness {
  const CheckWordConversionReadiness(this._probe);

  final MicrosoftWordProbe _probe;

  /// Returns the current Word-to-PDF conversion capability of this machine.
  ///
  /// Always returns a value; any probe-level failure is mapped to
  /// [MicrosoftWordUnavailable].
  Future<WordConversionCapability> call() async {
    try {
      final result = await _probe.probe();
      return switch (result) {
        MicrosoftWordFound(:final executablePath, :final version) =>
          MicrosoftWordAvailable(
            executablePath: executablePath,
            version: version,
          ),
        MicrosoftWordNotFound() => const MicrosoftWordUnavailable(),
      };
    } catch (_) {
      // The probe contract requires non-throwing, but a defensive catch here
      // ensures callers always receive a structured value regardless.
      return const MicrosoftWordUnavailable();
    }
  }
}
