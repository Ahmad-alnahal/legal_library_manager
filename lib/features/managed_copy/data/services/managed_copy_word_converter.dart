// lib/features/managed_copy/data/services/managed_copy_word_converter.dart
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import '../../../import/domain/services/file_hasher.dart';
import '../../../word_conversion/domain/services/microsoft_word_probe.dart';
import '../../../word_conversion/domain/services/word_converter.dart';
import '../../../word_conversion/domain/services/word_output_filesystem.dart';
import '../../domain/services/word_document_converter.dart';

/// Data-layer implementation of [WordDocumentConverter].
///
/// Wraps the existing [MicrosoftWordProbe], [WordConverter], and
/// [WordOutputFilesystem] abstractions. Creates a temporary `.doc` copy of
/// the original source file so the [WordConverter] contract (staged/app-owned
/// input path) is satisfied without staging permanently in the database.
///
/// All I/O is confined to [tempOutputDir]. The original source file is never
/// modified, moved, or deleted.
class ManagedCopyWordConverter implements WordDocumentConverter {
  const ManagedCopyWordConverter({
    required MicrosoftWordProbe probe,
    required WordConverter converter,
    required WordOutputFilesystem outputFs,
    required FileHasher hasher,
  }) : _probe = probe,
       _converter = converter,
       _outputFs = outputFs,
       _hasher = hasher;

  final MicrosoftWordProbe _probe;
  final WordConverter _converter;
  final WordOutputFilesystem _outputFs;
  final FileHasher _hasher;

  static const String _tempDocSuffix = '.word_src.doc';
  static const String _tempPdfSuffix = '.word_out';

  @override
  Future<WordDocumentConversionResult> convert({
    required String sourceDocPath,
    required String tempOutputDir,
    required String operationId,
  }) async {
    // 1. Probe Microsoft Word.
    final probeResult = await _probe.probe();
    if (probeResult is MicrosoftWordNotFound) {
      return const WordDocumentConversionFailed(
        safeMessage: 'Microsoft Word could not be found on this machine',
        errorCode: 'microsoft_word_unavailable',
      );
    }
    final executablePath = (probeResult as MicrosoftWordFound).executablePath;

    // 2. Ensure temp output directory exists.
    final dirResult = await _outputFs.ensureOutputDirectory(tempOutputDir);
    if (dirResult is OutputFailure) {
      return WordDocumentConversionFailed(
        safeMessage:
            'Word conversion temp directory could not be created: ${dirResult.safeMessage}',
        errorCode: 'temp_dir_unavailable',
      );
    }

    // 3. Create a temporary .doc copy inside tempOutputDir.
    //    The WordConverter contract requires an app-owned staged path, not the
    //    original user file. This copy is temporary and never persisted to DB.
    final tempDocPath = _pathJoin(tempOutputDir, '$operationId$_tempDocSuffix');
    try {
      await File(sourceDocPath).copy(tempDocPath);
    } catch (_) {
      return const WordDocumentConversionFailed(
        safeMessage: 'Could not create a temporary copy of the Word document',
        errorCode: 'temp_copy_failed',
      );
    }

    // 4. Run Word converter. Output path is inside tempOutputDir.
    final tempOutputPath = _pathJoin(
      tempOutputDir,
      '$operationId$_tempPdfSuffix',
    );
    final convResult = await _converter.convert(
      executablePath: executablePath,
      stagedPath: tempDocPath,
      outputPath: tempOutputPath,
    );

    // Clean up temporary .doc copy regardless of conversion outcome.
    try {
      await File(tempDocPath).delete();
    } catch (_) {
      // Best-effort; failure here does not affect the conversion result.
    }

    if (convResult is WordConverterFailed) {
      await _outputFs.deleteOutputFileSafe(tempOutputPath, tempOutputDir);
      return WordDocumentConversionFailed(
        safeMessage: convResult.safeMessage,
        errorCode: 'word_process_failed',
      );
    }
    final converterOutputPath =
        (convResult as WordConverterOutput).generatedPdfPath;

    // 5. Verify output file exists.
    if (!_outputFs.isExistingFile(converterOutputPath)) {
      return const WordDocumentConversionFailed(
        safeMessage: 'Microsoft Word did not create the expected output PDF',
        errorCode: 'output_not_created',
      );
    }

    // 6. Verify output is non-empty.
    final size = await _outputFs.fileSize(converterOutputPath);
    if (size == null || size == 0) {
      await _outputFs.deleteOutputFileSafe(converterOutputPath, tempOutputDir);
      return const WordDocumentConversionFailed(
        safeMessage: 'Generated PDF file is empty',
        errorCode: 'output_empty',
      );
    }

    // 7. Verify PDF header (%PDF, 0x25 0x50 0x44 0x46).
    final headerBytes = await _outputFs.readFirstBytes(converterOutputPath, 4);
    if (!_isPdfHeader(headerBytes)) {
      await _outputFs.deleteOutputFileSafe(converterOutputPath, tempOutputDir);
      return const WordDocumentConversionFailed(
        safeMessage: 'Generated file does not have a valid PDF header',
        errorCode: 'output_not_pdf',
      );
    }

    // 8. Hash the generated PDF.
    final hashResult = await _hasher.hashFile(converterOutputPath);
    if (!hashResult.isSuccess) {
      await _outputFs.deleteOutputFileSafe(converterOutputPath, tempOutputDir);
      return const WordDocumentConversionFailed(
        safeMessage: 'SHA-256 hashing of the generated PDF failed',
        errorCode: 'hash_failed',
      );
    }

    return WordDocumentConversionSuccess(
      tempPdfPath: converterOutputPath,
      pdfSha256: hashResult.hash!,
      fileSizeBytes: size,
    );
  }

  @override
  Future<void> cleanupSafely(String tempPdfPath, String tempDir) async {
    try {
      await _outputFs.deleteOutputFileSafe(tempPdfPath, tempDir);
    } catch (_) {
      // Best-effort cleanup — never throws.
    }
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
