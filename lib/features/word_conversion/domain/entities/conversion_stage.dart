// lib/features/word_conversion/domain/entities/conversion_stage.dart

/// Stage of a Word-to-PDF conversion currently in progress.
///
/// Only covers active execution stages. Terminal outcomes (success / failure)
/// are communicated via [WordConversionExecutionResult], not this enum.
/// No member represents a percentage — stage-based progress only.
enum ConversionStage {
  /// Pre-flight checks: loading records, probing Microsoft Word, verifying
  /// the staging area and output directory.
  preparing,

  /// Microsoft Word is opening the staged `.doc` source.
  openingDocument,

  /// Microsoft Word is running `ExportAsFixedFormat` to produce the PDF.
  exportingPdf,

  /// The generated PDF is being checked for existence, size, and `%PDF` header;
  /// its SHA-256 is being computed.
  validatingOutput,

  /// The output PDF is being renamed to its managed path and the result is
  /// being persisted to the database.
  savingResult,

  /// The temporary staging copy of the source `.doc` is being removed after a
  /// successful conversion. The managed PDF is already finalized at this point.
  cleaningUp,
}
