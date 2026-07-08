// lib/features/managed_copy/data/services/managed_copy_word_converter.dart
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import '../../../import/domain/services/file_hasher.dart';
import '../../../word_conversion/domain/services/microsoft_word_probe.dart';
import '../../../word_conversion/domain/services/word_converter.dart';
import '../../../word_conversion/domain/services/word_output_filesystem.dart';
import '../../domain/services/local_file_availability_checker.dart';
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
    required LocalFileAvailabilityChecker localFileChecker,
  }) : _probe = probe,
       _converter = converter,
       _outputFs = outputFs,
       _hasher = hasher,
       _localFileChecker = localFileChecker;

  final MicrosoftWordProbe _probe;
  final WordConverter _converter;
  final WordOutputFilesystem _outputFs;
  final FileHasher _hasher;
  final LocalFileAvailabilityChecker _localFileChecker;

  static const String _tempDocSuffix = '.word_src.doc';
  static const String _tempPdfSuffix = '.word_out';
  static const String _capabilityProbeSuffix = '.word_capability_probe.pdf';

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

    // 2.5. Verify the source is actually resident on local disk before ever
    // touching it. A OneDrive Files On-Demand (or similar cloud-sync)
    // "online-only" placeholder must never be read here — that would either
    // silently trigger a network download (violating the no-internet-
    // dependency rule) or fail unpredictably offline. Fail safely and
    // specifically instead.
    if (!_localFileChecker.isLocallyAvailable(sourceDocPath)) {
      return const WordDocumentConversionFailed(
        safeMessage:
            'The source Word document is not available on local disk '
            '(cloud placeholder) and cannot be converted offline',
        errorCode: 'source_not_available_offline',
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

    // 3.5. Strip the NTFS "Mark of the Web" (Zone.Identifier) from the staged
    // copy, if present. Word treats zone-tagged files as coming from an
    // untrusted location and opens them in Protected View, which silently
    // blocks headless COM automation even though the same file converts fine
    // when a user manually opens it and dismisses the Protected View banner.
    // This only touches the app-owned temp copy created above — the original
    // source file is never touched.
    await _stripZoneIdentifier(tempDocPath);

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

      // Secondary diagnostic: convert a throwaway blank document (no user
      // content, no user file) to determine whether Word's export pipeline
      // is broken for every document right now (e.g. requires online
      // activation/sign-in) versus a problem specific to this .doc. This
      // only runs after a real failure — never proactively or at startup —
      // and never fakes success or writes any managed-copy DB state.
      final capabilityProbePath = _pathJoin(
        tempOutputDir,
        '$operationId$_capabilityProbeSuffix',
      );
      final capabilityResult = await _converter.convertBlankDocument(
        executablePath: executablePath,
        outputPath: capabilityProbePath,
      );
      await _outputFs.deleteOutputFileSafe(capabilityProbePath, tempOutputDir);

      if (capabilityResult is WordConverterFailed) {
        return WordDocumentConversionFailed(
          safeMessage:
              'Microsoft Word cannot export any PDF right now — it may '
              'require online activation or sign-in: ${convResult.safeMessage}',
          errorCode: 'local_word_unavailable_offline_or_not_activated',
        );
      }
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

  /// Best-effort removal of the `:Zone.Identifier` alternate data stream that
  /// Windows attaches to files originating from the internet/network zone
  /// (email attachments, browser downloads, some network shares). Never
  /// throws: if the stream is absent or cannot be removed, conversion still
  /// proceeds — Word may show Protected View, and the downstream output
  /// checks (exists, non-empty, valid `%PDF` header) safely fail the
  /// conversion rather than fake success.
  Future<void> _stripZoneIdentifier(String path) async {
    try {
      final adsFile = File('$path:Zone.Identifier');
      if (adsFile.existsSync()) {
        adsFile.deleteSync();
      }
    } catch (_) {
      // Best-effort; see doc comment above.
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
