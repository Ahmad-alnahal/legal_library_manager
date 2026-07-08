// lib/features/word_conversion/domain/services/word_converter.dart

import '../entities/conversion_stage.dart';

/// Error codes for a Word-to-PDF conversion process call.
enum WordConverterError {
  /// The converter executable could not be launched (process exception).
  processLaunchFailed,

  /// The converter process ran but exited with a non-zero status code.
  conversionFailed,
}

/// Structured result of a single [WordConverter.convert] call.
sealed class WordConverterResult {
  const WordConverterResult();
}

/// The converter process completed successfully and placed a PDF at
/// [generatedPdfPath].
final class WordConverterOutput extends WordConverterResult {
  const WordConverterOutput({required this.generatedPdfPath});

  /// Absolute path to the PDF file placed by the converter in its output
  /// directory. The caller must verify the file exists, is non-empty, and
  /// carries a valid `%PDF` header before trusting this path.
  final String generatedPdfPath;
}

/// The converter process could not be launched or exited with an error.
/// No output file was produced (or any partial output is unreliable).
final class WordConverterFailed extends WordConverterResult {
  const WordConverterFailed({required this.error, required this.safeMessage});

  final WordConverterError error;

  /// Stable English error description — never contains raw process output,
  /// document content, or arbitrary command strings.
  final String safeMessage;
}

/// Injectable boundary for converting a Word document to PDF.
///
/// Implementations live in the data layer and may use `dart:io` and process
/// invocation APIs. Domain and application layers depend only on this
/// interface; they never import `dart:io` or invoke processes directly.
///
/// Contract: [convert] must never throw. All errors are mapped to
/// [WordConverterFailed] by the implementing class.
abstract class WordConverter {
  /// Converts the Word file at [stagedPath] to PDF, writing the output to the
  /// exact path [outputPath] using the automation host at [executablePath].
  ///
  /// [stagedPath] must point to an app-owned staged copy — never the original
  /// user source file. [outputPath] must be a full absolute path inside an
  /// app-owned directory; the caller is responsible for constructing it.
  ///
  /// [onStageChanged] is called synchronously when the converter transitions
  /// between [ConversionStage.openingDocument] and
  /// [ConversionStage.exportingPdf]. Callers must not depend on exact timing.
  ///
  /// Returns [WordConverterOutput] on success, [WordConverterFailed] on any
  /// error. Safe failure is required: the method must not propagate exceptions.
  Future<WordConverterResult> convert({
    required String executablePath,
    required String stagedPath,
    required String outputPath,
    void Function(ConversionStage stage)? onStageChanged,
  });

  /// Creates a throwaway blank document via local Word and exports it to PDF
  /// at [outputPath], to verify Word's automation and export pipeline is
  /// capable of producing a PDF right now — independent of any specific
  /// input file.
  ///
  /// Intended as a secondary diagnostic run only after [convert] has already
  /// failed for a real document, to distinguish a problem specific to that
  /// document (e.g. Protected View, corruption) from Word itself being
  /// unable to export any PDF at all (e.g. requires online activation or
  /// sign-in). No user document is ever opened or touched by this method.
  ///
  /// Returns [WordConverterOutput] on success, [WordConverterFailed] on any
  /// error. Must never throw.
  Future<WordConverterResult> convertBlankDocument({
    required String executablePath,
    required String outputPath,
  });
}
