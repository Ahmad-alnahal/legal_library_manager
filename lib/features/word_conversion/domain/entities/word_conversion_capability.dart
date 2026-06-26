// lib/features/word_conversion/domain/entities/word_conversion_capability.dart

/// Structured result of the Microsoft Word capability check.
///
/// [converterKey] on [MicrosoftWordAvailable] matches the `converter_key` value
/// stored in `file_conversions` rows (spec §8.1). No filesystem or process
/// state escapes this entity: only safe, serialisable fields are exposed.
sealed class WordConversionCapability {
  const WordConversionCapability();
}

/// Microsoft Word is installed and available for local Word-to-PDF conversion.
final class MicrosoftWordAvailable extends WordConversionCapability {
  const MicrosoftWordAvailable({required this.executablePath, this.version});

  /// Automation host used to drive the local Microsoft Word installation.
  final String executablePath;

  /// `converter_key` for `file_conversions` rows produced by Microsoft Word.
  static const String converterKey = 'microsoft_word';

  /// Parsed Word version string, or null when version output could not be
  /// parsed reliably.
  final String? version;
}

/// Microsoft Word could not be found or the capability probe failed safely.
///
/// No conversion can be attempted until Microsoft Word is installed/licensed
/// locally and the capability check succeeds.
final class MicrosoftWordUnavailable extends WordConversionCapability {
  const MicrosoftWordUnavailable();
}
