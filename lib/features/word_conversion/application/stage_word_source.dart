// lib/features/word_conversion/application/stage_word_source.dart

import '../../../core/time/clock.dart';
import '../domain/entities/word_conversion_capability.dart';
import '../domain/entities/word_source_file.dart';
import '../domain/entities/word_staging_error.dart';
import '../domain/entities/word_staging_result.dart';
import '../domain/repositories/word_conversion_repository.dart';
import '../domain/services/word_staging_filesystem.dart';

/// Copies a registered Word source file into the app-owned staging area and
/// persists a `file_conversions` row with `status_key = pending_conversion`.
///
/// P1.2 scope: staging only. No Word conversion is performed and no
/// conversion-quality review UI is activated. The original source file is
/// never modified, renamed, or deleted.
///
/// No dart:io, Drift, FFI, shell, or Windows API imports are permitted in
/// this file or any file in domain / application.
class StageWordSource {
  const StageWordSource({
    required this._repository,
    required this._filesystem,
    required this._clock,
  });

  final WordConversionRepository _repository;
  final WordStagingFilesystem _filesystem;
  final Clock _clock;

  static const String _stagingDirName = 'WordStaging';
  static const String _sourceOriginalRole = 'source_original';

  /// Stages [sourceFileId] into the app-owned Word staging area.
  ///
  /// The operation is idempotent: calling this twice for the same file returns
  /// [WordStagingAlreadyStaged] on the second call without re-copying bytes.
  /// Returns a structured [WordStagingResult] — never throws.
  Future<WordStagingResult> call(int sourceFileId) async {
    // ── 1. Load source record ─────────────────────────────────────────────────

    final source = await _repository.loadSourceRecord(sourceFileId);
    if (source == null) {
      return const WordStagingBlocked(
        error: WordStagingError.sourceFileNotFound,
        safeMessage: 'source file record not found',
      );
    }

    // ── 2. Validate role ──────────────────────────────────────────────────────

    if (source.fileRoleKey != _sourceOriginalRole) {
      return const WordStagingBlocked(
        error: WordStagingError.sourceFileNotWordDocument,
        safeMessage: 'source file is not a source_original record',
      );
    }

    // ── 3. Validate extension ─────────────────────────────────────────────────

    if (!kWordExtensions.contains(source.extension.toLowerCase())) {
      return const WordStagingBlocked(
        error: WordStagingError.sourceFileNotWordDocument,
        safeMessage: 'source file is not a Word document',
      );
    }

    // ── 4. Require a known hash ───────────────────────────────────────────────

    final sha256 = source.sha256Hash;
    if (sha256 == null || sha256.isEmpty) {
      return const WordStagingBlocked(
        error: WordStagingError.sourceHashNotAvailable,
        safeMessage: 'source file hash not available',
      );
    }

    // ── 5. Load managed library root ──────────────────────────────────────────

    final managedRoot = await _repository.loadManagedLibraryRoot();
    if (managedRoot == null || managedRoot.trim().isEmpty) {
      return const WordStagingBlocked(
        error: WordStagingError.noManagedLibraryRoot,
        safeMessage: 'managed library root not configured',
      );
    }

    // ── 6. Derive content-addressed staging paths ─────────────────────────────

    final stagingDir = _pathJoin(managedRoot, _stagingDirName);
    final stagedPath = _pathJoin(stagingDir, '$sha256${source.extension}');
    final tempPath = '$stagedPath.staging';

    // ── 7. Idempotency check ──────────────────────────────────────────────────

    final existing = await _repository.findActiveConversion(sourceFileId);
    if (existing != null) {
      return WordStagingAlreadyStaged(
        stagedPath: stagedPath,
        conversionId: existing.conversionId,
      );
    }

    // ── 8. Ensure staging directory ───────────────────────────────────────────

    final ensureResult = await _filesystem.ensureStagingDirectory(stagingDir);
    if (ensureResult is StagingFailure) {
      return const WordStagingBlocked(
        error: WordStagingError.stagingDirectoryUnavailable,
        safeMessage: 'staging directory unavailable',
      );
    }

    // ── 9. Copy source to staging area ────────────────────────────────────────

    // Skip copy when the staged file already exists on disk (recovery scenario:
    // a previous run may have completed the copy but crashed before the DB
    // write). The file is content-addressed by sha256, so an existing file
    // with the correct name is guaranteed to have the correct content.
    if (!_filesystem.isExistingFile(stagedPath)) {
      final copyResult = await _filesystem.copyToTemp(
        source.absolutePath,
        tempPath,
      );
      if (copyResult is StagingFailure) {
        await _filesystem.deleteTempSafe(tempPath, stagingDir);
        return const WordStagingFailed(
          error: WordStagingError.stagingCopyFailed,
          safeMessage: 'staging copy failed',
        );
      }

      final finalizeResult = await _filesystem.finalize(tempPath, stagedPath);
      if (finalizeResult is StagingFailure) {
        await _filesystem.deleteTempSafe(tempPath, stagingDir);
        return const WordStagingFailed(
          error: WordStagingError.stagingCopyFailed,
          safeMessage: 'staging finalization failed',
        );
      }
    }

    // ── 10. Persist conversion record ─────────────────────────────────────────

    try {
      final now = _clock.nowUtc();
      final nowIso = now.toIso8601String();
      final operationId =
          '${source.documentId}-word-stage-$sourceFileId-${now.millisecondsSinceEpoch}';
      final conversionId = await _repository.persistConversionRecord(
        documentId: source.documentId,
        sourceFileId: sourceFileId,
        converterKey: MicrosoftWordAvailable.converterKey,
        operationId: operationId,
        nowIso: nowIso,
      );
      return WordStagingSuccess(
        stagedPath: stagedPath,
        conversionId: conversionId,
      );
    } catch (_) {
      return const WordStagingFailed(
        error: WordStagingError.persistenceFailed,
        safeMessage: 'conversion record persistence failed',
      );
    }
  }

  /// Joins two Windows path segments, normalizing forward slashes and
  /// stripping any trailing separator from [base].
  static String _pathJoin(String base, String part) {
    final b = base.replaceAll('/', r'\');
    final trimmed = (b.length > 3 && b.endsWith(r'\'))
        ? b.substring(0, b.length - 1)
        : b;
    return '$trimmed\\$part';
  }
}
