// lib/features/word_conversion/application/convert_staged_word_source.dart

import '../../import/domain/entities/sha256_result.dart';
import '../../import/domain/services/file_hasher.dart';
import '../domain/entities/conversion_stage.dart';
import '../domain/entities/word_conversion_execution_error.dart';
import '../domain/entities/word_conversion_execution_result.dart';
import '../domain/repositories/word_conversion_repository.dart';
import '../domain/services/microsoft_word_probe.dart';
import '../domain/services/word_converter.dart';
import '../domain/services/word_output_filesystem.dart';
import '../domain/services/word_staging_filesystem.dart';

/// Executes a staged Word-to-PDF conversion using local Microsoft Word.
///
/// Operates exclusively on app-owned paths. It never reads, modifies, moves,
/// or deletes the original user source file. It never passes the original
/// source path to any process or filesystem call.
///
/// On success the generated PDF is saved to the `WordStaging/` directory as
/// `<sha256>.pdf` (content-addressed, alongside the staged `.doc` source), and
/// the staged `.doc` copy is removed.  No document code is allocated here:
/// `document_code` remains null until the document is accepted into the
/// managed-library workflow via [ManagedCopyUseCase].
///
/// Call [call] with the `file_conversions.id` of a row in
/// `pending_conversion` status that was created by [StageWordSource].
class ConvertStagedWordSource {
  const ConvertStagedWordSource({
    required this._repository,
    required this._probe,
    required this._converter,
    required this._outputFs,
    required this._stagingFs,
    required this._hasher,
  });

  final WordConversionRepository _repository;
  final MicrosoftWordProbe _probe;
  final WordConverter _converter;
  final WordOutputFilesystem _outputFs;
  final WordStagingFilesystem _stagingFs;
  final FileHasher _hasher;

  static const String _stagingDirName = 'WordStaging';
  static const String _tempSuffix = '.converting';

  // ── Entry point ─────────────────────────────────────────────────────────────

  Future<WordConversionExecutionResult> call(
    int conversionId, {
    void Function(ConversionStage stage)? onStageChanged,
  }) async {
    // 1. Load conversion record.
    final record = await _repository.loadConversionForExecution(conversionId);
    if (record == null) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.conversionNotFound,
        safeMessage: 'no conversion record found for this ID',
      );
    }

    // 2. Inspect status.
    switch (record.statusKey) {
      case 'needs_conversion_review':
      case 'conversion_approved':
      case 'conversion_succeeded':
        return WordConversionAlreadyCompleted(statusKey: record.statusKey);
      case 'converting':
        return const WordConversionExecutionBlocked(
          error: WordConversionExecutionError.conversionAlreadyInProgress,
          safeMessage:
              'conversion is already in progress; reset is required before retrying',
        );
      case 'pending_conversion':
        break; // proceed
      default:
        return const WordConversionExecutionBlocked(
          error: WordConversionExecutionError.conversionNotPending,
          safeMessage: 'conversion is not in a retryable state',
        );
    }

    // 3. Load source file record.
    final source = await _repository.loadSourceRecord(record.sourceFileId);
    if (source == null) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.sourceNotFound,
        safeMessage: 'source file record not found',
      );
    }

    // 4. Load managed library root.
    final root = await _repository.loadManagedLibraryRoot();
    if (root == null || root.trim().isEmpty) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.libraryRootNotConfigured,
        safeMessage: 'managed library root is not configured',
      );
    }

    // 5. Verify staged file exists (sha256Hash is the staged file stem).
    final sha256Word = source.sha256Hash;
    if (sha256Word == null || sha256Word.isEmpty) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.stagedFileNotFound,
        safeMessage: 'source hash is missing; cannot locate staged file',
      );
    }
    final stagingDir = _pathJoin(root, _stagingDirName);
    final stagedPath = _pathJoin(stagingDir, '$sha256Word${source.extension}');
    if (!_stagingFs.isExistingFile(stagedPath)) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.stagedFileNotFound,
        safeMessage: 'staged Word file is missing from the staging area',
      );
    }

    // 6. Probe Microsoft Word.
    onStageChanged?.call(ConversionStage.preparing);
    final probeResult = await _probe.probe();
    if (probeResult is MicrosoftWordNotFound) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.microsoftWordUnavailable,
        safeMessage: 'Microsoft Word could not be found on this machine',
      );
    }
    final executablePath = (probeResult as MicrosoftWordFound).executablePath;

    // 7. Ensure staging directory (already created by StageWordSource; guard
    //    against any race that removed it before conversion runs).
    final dirResult = await _outputFs.ensureOutputDirectory(stagingDir);
    if (dirResult is OutputFailure) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.outputDirectoryUnavailable,
        safeMessage: 'staging directory could not be verified',
      );
    }

    // 8. Mark converting — only proceeds if status is still pending_conversion.
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    final operationId =
        '${record.documentId}-word-convert-$conversionId-${now.millisecondsSinceEpoch}';
    final didMark = await _repository.markConverting(conversionId, nowIso);
    if (!didMark) {
      return const WordConversionExecutionBlocked(
        error: WordConversionExecutionError.conversionAlreadyInProgress,
        safeMessage: 'conversion status changed unexpectedly; try again later',
      );
    }

    // Temp path uses operationId for uniqueness; the final content-addressed
    // name (<sha256>.pdf) is derived after hashing in step 13.
    final tempOutputPath = _pathJoin(stagingDir, '$operationId$_tempSuffix');

    // 9–15 run after markConverting; all failures must call _recordFailure and
    // attempt to clean up tempOutputPath.

    // 9. Run Microsoft Word converter.
    final convResult = await _converter.convert(
      executablePath: executablePath,
      stagedPath: stagedPath,
      outputPath: tempOutputPath,
      onStageChanged: onStageChanged,
    );
    if (convResult is WordConverterFailed) {
      await _outputFs.deleteOutputFileSafe(tempOutputPath, stagingDir);
      return await _recordFailure(
        conversionId: conversionId,
        documentId: record.documentId,
        sourceFileId: record.sourceFileId,
        errorCode: 'process_failed',
        errorMessageSafe: convResult.safeMessage,
        operationId: operationId,
        nowIso: nowIso,
        error: WordConversionExecutionError.processFailed,
        safeMessage: convResult.safeMessage,
      );
    }
    final converterOutput =
        (convResult as WordConverterOutput).generatedPdfPath;

    // 10. Verify output file exists.
    onStageChanged?.call(ConversionStage.validatingOutput);
    if (!_outputFs.isExistingFile(converterOutput)) {
      return await _recordFailure(
        conversionId: conversionId,
        documentId: record.documentId,
        sourceFileId: record.sourceFileId,
        errorCode: 'output_not_created',
        errorMessageSafe:
            'Microsoft Word did not create the expected output file',
        operationId: operationId,
        nowIso: nowIso,
        error: WordConversionExecutionError.outputNotCreated,
        safeMessage: 'conversion did not produce a PDF file',
      );
    }

    // 11. Verify output is non-empty.
    final size = await _outputFs.fileSize(converterOutput);
    if (size == null || size == 0) {
      await _outputFs.deleteOutputFileSafe(converterOutput, stagingDir);
      return await _recordFailure(
        conversionId: conversionId,
        documentId: record.documentId,
        sourceFileId: record.sourceFileId,
        errorCode: 'output_empty',
        errorMessageSafe: 'generated PDF file is empty',
        operationId: operationId,
        nowIso: nowIso,
        error: WordConversionExecutionError.outputEmpty,
        safeMessage: 'generated PDF file is empty',
      );
    }

    // 12. Verify PDF header (%PDF, 0x25 0x50 0x44 0x46).
    final headerBytes = await _outputFs.readFirstBytes(converterOutput, 4);
    if (!_isPdfHeader(headerBytes)) {
      await _outputFs.deleteOutputFileSafe(converterOutput, stagingDir);
      return await _recordFailure(
        conversionId: conversionId,
        documentId: record.documentId,
        sourceFileId: record.sourceFileId,
        errorCode: 'output_not_pdf',
        errorMessageSafe: 'generated file does not have a valid PDF header',
        operationId: operationId,
        nowIso: nowIso,
        error: WordConversionExecutionError.outputNotPdf,
        safeMessage: 'generated file does not appear to be a valid PDF',
      );
    }

    // 13. Hash the generated PDF, then derive the content-addressed output name.
    final Sha256Result hashResult = await _hasher.hashFile(converterOutput);
    if (!hashResult.isSuccess) {
      await _outputFs.deleteOutputFileSafe(converterOutput, stagingDir);
      return await _recordFailure(
        conversionId: conversionId,
        documentId: record.documentId,
        sourceFileId: record.sourceFileId,
        errorCode: 'hash_failed',
        errorMessageSafe: 'SHA-256 hashing of the generated PDF failed',
        operationId: operationId,
        nowIso: nowIso,
        error: WordConversionExecutionError.hashFailed,
        safeMessage: 'could not compute a hash for the generated PDF',
      );
    }
    final pdfSha256 = hashResult.hash!;

    // Final output name: <sha256>.pdf stored in WordStaging alongside the
    // source .doc file.  The document_code is NOT allocated here; it is
    // deferred to the managed-copy workflow so the review queue remains
    // consistent between plain-PDF and Word-converted documents.
    final outputFileName = '$pdfSha256.pdf';
    final finalPath = _pathJoin(stagingDir, outputFileName);

    // 14. Rename temp file to the content-addressed staging name.
    onStageChanged?.call(ConversionStage.savingResult);
    final renameResult = await _outputFs.renameOutputFile(
      converterOutput,
      finalPath,
    );
    if (renameResult is OutputFailure) {
      await _outputFs.deleteOutputFileSafe(converterOutput, stagingDir);
      return await _recordFailure(
        conversionId: conversionId,
        documentId: record.documentId,
        sourceFileId: record.sourceFileId,
        errorCode: 'output_rename_failed',
        errorMessageSafe: 'could not finalize output PDF path',
        operationId: operationId,
        nowIso: nowIso,
        error: WordConversionExecutionError.persistenceFailed,
        safeMessage: 'could not finalize the PDF output file',
      );
    }

    // 15. Persist success.
    final WordConversionExecutionResult persistResult;
    try {
      final outputFileId = await _repository.finalizeSuccessfulConversion(
        conversionId: conversionId,
        documentId: record.documentId,
        sourceFileId: record.sourceFileId,
        outputPath: finalPath,
        outputFileName: outputFileName,
        pdfSha256: pdfSha256,
        fileSizeBytes: size,
        operationId: operationId,
        nowIso: nowIso,
      );
      persistResult = WordConversionExecutionSuccess(
        outputFileId: outputFileId,
        outputPath: finalPath,
        pdfSha256: pdfSha256,
      );
    } catch (_) {
      try {
        await _repository.recordFailedConversion(
          conversionId: conversionId,
          documentId: record.documentId,
          sourceFileId: record.sourceFileId,
          errorCode: 'persistence_failed',
          errorMessageSafe: 'conversion record finalization failed',
          operationId: operationId,
          nowIso: nowIso,
        );
      } catch (_) {
        // Double-failure: the status remains in 'converting'.
      }
      return const WordConversionExecutionFailed(
        error: WordConversionExecutionError.persistenceFailed,
        safeMessage: 'conversion record finalization failed',
      );
    }

    // 16. Clean up staged Word copy (best-effort — success already recorded).
    onStageChanged?.call(ConversionStage.cleaningUp);
    await _stagingFs.deleteStagedFileSafe(stagedPath, stagingDir);

    return persistResult;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<WordConversionExecutionFailed> _recordFailure({
    required int conversionId,
    required int documentId,
    required int sourceFileId,
    required String errorCode,
    required String errorMessageSafe,
    required String operationId,
    required String nowIso,
    required WordConversionExecutionError error,
    required String safeMessage,
  }) async {
    try {
      await _repository.recordFailedConversion(
        conversionId: conversionId,
        documentId: documentId,
        sourceFileId: sourceFileId,
        errorCode: errorCode,
        errorMessageSafe: errorMessageSafe,
        operationId: operationId,
        nowIso: nowIso,
      );
    } catch (_) {
      // Failure recording itself failed; the error is still surfaced to caller.
    }
    return WordConversionExecutionFailed(
      error: error,
      safeMessage: safeMessage,
    );
  }

  static bool _isPdfHeader(List<int>? bytes) {
    if (bytes == null || bytes.length < 4) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  static String _pathJoin(String base, String part) {
    final b = base.replaceAll('/', r'\');
    final trimmed = (b.length > 3 && b.endsWith(r'\'))
        ? b.substring(0, b.length - 1)
        : b;
    return '$trimmed\\$part';
  }
}
