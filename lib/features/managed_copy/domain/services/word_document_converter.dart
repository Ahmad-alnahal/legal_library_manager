// lib/features/managed_copy/domain/services/word_document_converter.dart

/// Result of a [WordDocumentConverter.convert] call.
sealed class WordDocumentConversionResult {
  const WordDocumentConversionResult();
}

/// The `.doc` file was successfully converted to a temporary PDF.
///
/// [tempPdfPath] is the absolute path of the temporary PDF inside the caller's
/// temp directory. The caller MUST delete it via [WordDocumentConverter.cleanupSafely]
/// when the managed-copy flow completes (success or failure).
final class WordDocumentConversionSuccess extends WordDocumentConversionResult {
  const WordDocumentConversionSuccess({
    required this.tempPdfPath,
    required this.pdfSha256,
    required this.fileSizeBytes,
  });

  final String tempPdfPath;
  final String pdfSha256;
  final int fileSizeBytes;
}

/// The conversion failed before a usable PDF was produced.
///
/// No temp file was left behind (the implementation deletes any partial output).
final class WordDocumentConversionFailed extends WordDocumentConversionResult {
  const WordDocumentConversionFailed({
    required this.safeMessage,
    required this.errorCode,
  });

  final String safeMessage;
  final String errorCode;
}

/// Domain boundary for converting a `.doc` file to a temporary PDF.
///
/// Implementations live in the data layer and may use `dart:io`, process APIs,
/// and Word conversion infrastructure. Domain and application layers depend
/// only on this abstraction.
///
/// Contract:
/// - [convert] must never throw — all errors are [WordDocumentConversionFailed].
/// - [convert] never modifies, moves, or deletes [sourceDocPath].
/// - The temp PDF is written inside [tempOutputDir]; no other directory is
///   written to.
/// - When [convert] returns [WordDocumentConversionFailed], no temp file remains.
/// - [cleanupSafely] must never throw — cleanup failures are swallowed.
abstract class WordDocumentConverter {
  /// Converts the `.doc` file at [sourceDocPath] to a temporary PDF.
  ///
  /// [sourceDocPath] must point to an existing readable `.doc` file.
  /// [tempOutputDir] must be an existing application-owned directory.
  /// [operationId] is used to derive a unique temp filename.
  ///
  /// On success: returns [WordDocumentConversionSuccess] with the temp PDF path
  /// and its verified SHA-256 hash and byte count.
  /// On failure: returns [WordDocumentConversionFailed] with no temp file left.
  Future<WordDocumentConversionResult> convert({
    required String sourceDocPath,
    required String tempOutputDir,
    required String operationId,
  });

  /// Deletes [tempPdfPath] when it is directly inside [tempDir].
  ///
  /// Best-effort: never throws. Path-safety violations are silently ignored so
  /// this call never masks the primary result.
  Future<void> cleanupSafely(String tempPdfPath, String tempDir);
}
