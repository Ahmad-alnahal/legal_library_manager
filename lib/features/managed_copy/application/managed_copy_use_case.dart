// lib/features/managed_copy/application/managed_copy_use_case.dart
// ignore_for_file: prefer_initializing_formals

import '../../../core/time/clock.dart';
import '../../import/domain/services/file_hasher.dart';
import '../domain/entities/copy_roots.dart';
import '../domain/entities/document_copy_state.dart';
import '../domain/entities/managed_copy_error.dart';
import '../domain/entities/managed_copy_persistence_data.dart';
import '../domain/entities/managed_copy_result.dart';
import '../domain/entities/source_file_candidate.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/database_backup_service.dart';
import '../domain/services/managed_library_filesystem.dart';
import '../domain/services/operation_id_generator.dart';
import '../domain/services/path_canonicalizer.dart';
import '../domain/services/word_document_converter.dart';

/// Orchestrates the full managed-copy workflow for a single document.
///
/// Accepts only a registered [documentId]. Never accepts arbitrary paths.
/// Never modifies source files. Uses one atomic DB transaction for success
/// persistence only after the copy is finalized and hash-verified.
///
/// No dart:io, Drift, FFI, shell, or Windows API imports are permitted in
/// this file or any file in domain/application.
class ManagedCopyUseCase {
  const ManagedCopyUseCase({
    required ManagedCopyRepository repository,
    required ManagedLibraryFilesystem filesystem,
    required DatabaseBackupService backupService,
    required FileHasher hasher,
    required Clock clock,
    required PathCanonicalizer pathCanonicalizer,
    required OperationIdGenerator operationIdGenerator,
    WordDocumentConverter? wordConverter,
  }) : _repository = repository,
       _filesystem = filesystem,
       _backupService = backupService,
       _hasher = hasher,
       _clock = clock,
       _pathCanonicalizer = pathCanonicalizer,
       _operationIdGenerator = operationIdGenerator,
       _wordConverter = wordConverter;

  final ManagedCopyRepository _repository;
  final ManagedLibraryFilesystem _filesystem;
  final DatabaseBackupService _backupService;
  final FileHasher _hasher;
  final Clock _clock;
  final PathCanonicalizer _pathCanonicalizer;
  final OperationIdGenerator _operationIdGenerator;

  /// Optional Word converter. Required when a `.doc` source is selected.
  /// When null, `.doc` sources are rejected with [ManagedCopyError.unsupportedSource].
  final WordDocumentConverter? _wordConverter;

  Future<ManagedCopyResult> execute(int documentId) async {
    final DateTime now = _clock.nowUtc();
    final String operationId = _operationIdGenerator.generate(now);

    // ── 1. Load and validate database state ──────────────────────────────────

    DocumentCopyState? docState = await _repository.loadDocumentState(
      documentId,
    );
    if (docState == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.documentNotFound,
        safeMessage: 'Document not found.',
      );
    }

    final reconciliation = await _reconcileManagedCopyFiles(
      documentId: documentId,
      operationId: operationId,
      now: now,
    );
    if (!reconciliation.succeeded) {
      return const ManagedCopyFailed(
        error: ManagedCopyError.unexpectedFailure,
        safeMessage: 'Managed-copy state could not be reconciled safely.',
      );
    }
    if (reconciliation.changed) {
      docState = await _repository.loadDocumentState(documentId);
      if (docState == null) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.documentNotFound,
          safeMessage: 'Document not found.',
        );
      }
    }

    if (docState.hasHealthyManagedCopy &&
        docState.workflowStatusKey == 'copied_to_library') {
      // Differentiate: file was just restored from disk by reconciliation above
      // (user moved it back) vs it was already healthy before this call.
      if (reconciliation.anyRestored) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.restoredFromDisk,
          safeMessage: 'Missing managed copy found on disk and restored.',
        );
      }
      return const ManagedCopyBlocked(
        error: ManagedCopyError.alreadyCopied,
        safeMessage: 'Document already has a managed copy.',
      );
    }
    if (docState.workflowStatusKey != 'classified') {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.notClassified,
        safeMessage:
            'Document must be classified before copying to the library.',
      );
    }

    // ── Load and validate configured roots ───────────────────────────────────

    final CopyRoots roots = await _repository.loadCopyRoots();
    if (!roots.areBothConfigured) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.rootsNotConfigured,
        safeMessage:
            'Managed library root and database backup root must both be configured.',
      );
    }

    final String managedRoot = roots.managedLibraryRoot!;
    final String backupRoot = roots.backupRoot!;

    if (!_isAbsolutePath(managedRoot)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage: 'Managed library root is not an absolute path.',
      );
    }
    if (!_filesystem.isExistingDirectory(managedRoot)) {
      // Absolute but missing/inaccessible: storage requires attention. The user
      // can explicitly recreate it from Settings (M8.5).
      return const ManagedCopyBlocked(
        error: ManagedCopyError.rootsMissing,
        safeMessage: 'Managed library root directory is missing.',
      );
    }
    if (!_isAbsolutePath(backupRoot)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage: 'Database backup root is not an absolute path.',
      );
    }
    if (!_filesystem.isExistingDirectory(backupRoot)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.rootsMissing,
        safeMessage: 'Database backup root directory is missing.',
      );
    }

    final String databaseRoot = await _repository.loadDatabaseRoot();
    final String managedFilesDir = _pathJoin(managedRoot, 'files');

    // ── 2. Canonical path resolution ─────────────────────────────────────────
    // Resolve each root to its canonical form before overlap checks.
    // This catches .. aliases, symbolic links, and Windows junctions/reparse
    // points that would otherwise bypass lowercased-string comparisons.

    final String? canonManagedRoot = _pathCanonicalizer.canonicalize(
      managedRoot,
    );
    if (canonManagedRoot == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage:
            'Managed library root could not be resolved to a canonical path.',
      );
    }

    final String? canonBackupRoot = _pathCanonicalizer.canonicalize(backupRoot);
    if (canonBackupRoot == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage:
            'Database backup root could not be resolved to a canonical path.',
      );
    }

    final String? canonDatabaseRoot = _pathCanonicalizer.canonicalize(
      databaseRoot,
    );
    if (canonDatabaseRoot == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage:
            'Application support root could not be resolved to a canonical path.',
      );
    }

    // The files subdirectory may not exist yet; resolve it when it does,
    // otherwise derive from the already-canonical managed root.
    final String canonFilesDir =
        _pathCanonicalizer.canonicalize(managedFilesDir) ??
        _pathJoin(canonManagedRoot, 'files');

    // ── 3. Overlap checks (all using canonical paths) ─────────────────────────

    if (_pathIsInsideOrEquals(canonBackupRoot, canonManagedRoot) ||
        _pathIsInsideOrEquals(canonManagedRoot, canonBackupRoot)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage: 'Backup root and managed library root must not overlap.',
      );
    }
    if (_pathIsInsideOrEquals(canonBackupRoot, canonFilesDir)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage: 'Backup root must not be inside managed files directory.',
      );
    }
    if (_pathIsInsideOrEquals(canonFilesDir, canonDatabaseRoot) ||
        _pathIsInsideOrEquals(canonDatabaseRoot, canonFilesDir)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage:
            'Managed files directory must not overlap with the database root.',
      );
    }
    if (_pathIsInsideOrEquals(canonBackupRoot, canonDatabaseRoot) ||
        _pathIsInsideOrEquals(canonDatabaseRoot, canonBackupRoot)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage: 'Backup root must not overlap with the database root.',
      );
    }

    // Source-location overlap: resolve every registered source parent. A
    // missing/unresolvable parent cannot be proven separate from the managed
    // and backup roots, so fail closed.
    final List<String> sourcePaths = await _repository.loadDocumentSourcePaths(
      documentId,
    );
    final List<String> canonicalSourceParents = [];
    for (final sp in sourcePaths) {
      final String? sourceParent = _pathCanonicalizer.canonicalize(
        _parentDir(sp),
      );
      if (sourceParent == null) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.unsafeRoots,
          safeMessage:
              'A registered source location could not be resolved safely.',
        );
      }
      canonicalSourceParents.add(sourceParent);
      if (_pathsOverlap(canonManagedRoot, sourceParent) ||
          _pathsOverlap(canonBackupRoot, sourceParent) ||
          _pathsOverlap(canonFilesDir, sourceParent)) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.unsafeRoots,
          safeMessage:
              'Managed and backup roots must not overlap source locations.',
        );
      }
    }

    // ── 4. Select eligible source file ───────────────────────────────────────

    final List<SourceFileCandidate> candidates = await _repository
        .loadEligibleSources(documentId);

    final List<SourceFileCandidate> eligible = candidates
        .where(_isEligibleCandidate)
        .toList();

    if (eligible.isEmpty) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.noEligibleSource,
        safeMessage: 'No eligible source_original healthy PDF file found.',
      );
    }

    final SourceFileCandidate? source = _selectSource(eligible);
    if (source == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.ambiguousSource,
        safeMessage:
            'Multiple eligible sources exist with no uniquely preferred file.',
      );
    }

    // Determine whether this is a .doc source requiring in-flow Word conversion.
    final String actualSourceExt = _pathExtension(
      source.absolutePath,
    ).toLowerCase();
    final bool isDocSource = actualSourceExt == '.doc';

    if (actualSourceExt != '.pdf' && actualSourceExt != '.doc') {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsupportedSource,
        safeMessage: 'Source file path extension must be .pdf or .doc.',
      );
    }

    if (isDocSource && _wordConverter == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsupportedSource,
        safeMessage:
            'Word document source requires a configured Word converter.',
      );
    }

    // Source must physically exist.
    if (!_filesystem.isExistingFile(source.absolutePath)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.missingSource,
        safeMessage: 'Source file does not exist on the filesystem.',
      );
    }

    // Canonicalize the selected source path to detect symlinks/junctions that
    // might point into the managed library.
    final String? canonSourcePath = _pathCanonicalizer.canonicalize(
      source.absolutePath,
    );
    if (canonSourcePath == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.missingSource,
        safeMessage:
            'Source file path could not be resolved to a canonical path.',
      );
    }

    if (_pathIsInsideOrEquals(canonSourcePath, canonFilesDir)) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage:
            'Source file must not be inside the managed files directory.',
      );
    }

    // ── 5. Word conversion (for .doc sources) ─────────────────────────────────
    //
    // This must happen BEFORE any document_code allocation or DB write. If
    // Word conversion fails (including when local Word cannot run offline),
    // the document must not get a new document_code and no managed_copy row
    // may ever be created. The temp PDF (if any) lives in a true local,
    // non-cloud-synced application temp folder — never inside the managed
    // library, backup root, or any OneDrive/cloud-synced location — named
    // from operationId, never from a document code, since no code exists yet
    // at this point.
    //
    // For .pdf sources this whole step is skipped; the trusted hash is
    // resolved later, inside _executeAfterTempSetup, from the stored or
    // freshly computed SHA-256 of the source file.

    String wordTempDir = '';
    String wordTempPdfPath = '';
    String? docTrustedHash;

    if (isDocSource) {
      final String wordTempParent = await _repository.loadWordTempRoot();
      if (!_isAbsolutePath(wordTempParent)) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.unsafeRoots,
          safeMessage:
              'Word conversion temp directory is not an absolute path.',
        );
      }

      // Defensive overlap check: the local temp root is expected to be
      // structurally separate from the managed library and backup root by
      // construction (it resolves under the OS local temp folder), but this
      // is verified explicitly rather than assumed. The temp folder may not
      // exist yet on first use, so canonicalization falls back to the raw
      // path when resolution fails — matching the same fallback already used
      // for the managed files directory below.
      final String probeWordTempParent =
          _pathCanonicalizer.canonicalize(wordTempParent) ?? wordTempParent;
      if (_pathsOverlap(probeWordTempParent, canonManagedRoot) ||
          _pathsOverlap(probeWordTempParent, canonFilesDir) ||
          _pathsOverlap(probeWordTempParent, canonBackupRoot)) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.unsafeRoots,
          safeMessage:
              'Word conversion temp directory must not overlap the managed '
              'library or backup root.',
        );
      }

      final parentDirResult = await _filesystem.ensureDirectoryExists(
        wordTempParent,
      );
      if (parentDirResult is FilesystemFailure) {
        await _tryAppendEvent(
          documentId: documentId,
          fileId: source.fileId,
          operationId: operationId,
          eventTypeKey: 'copy_failed',
          resultKey: 'failed',
          errorCode: ManagedCopyError.wordConversionFailed.name,
          messageSafe: 'Word conversion temp directory could not be created.',
        );
        return const ManagedCopyFailed(
          error: ManagedCopyError.wordConversionFailed,
          safeMessage: 'Word conversion temp directory could not be created.',
        );
      }

      final String candidateWordTempDir = _pathJoin(
        wordTempParent,
        'WordConversionTemp',
      );

      final wordTempDirResult = await _filesystem.ensureDirectoryExists(
        candidateWordTempDir,
      );
      if (wordTempDirResult is FilesystemFailure) {
        await _tryAppendEvent(
          documentId: documentId,
          fileId: source.fileId,
          operationId: operationId,
          eventTypeKey: 'copy_failed',
          resultKey: 'failed',
          errorCode: ManagedCopyError.wordConversionFailed.name,
          messageSafe: 'Word conversion temp directory could not be created.',
        );
        return const ManagedCopyFailed(
          error: ManagedCopyError.wordConversionFailed,
          safeMessage: 'Word conversion temp directory could not be created.',
        );
      }

      final convResult = await _wordConverter!.convert(
        sourceDocPath: source.absolutePath,
        tempOutputDir: candidateWordTempDir,
        operationId: operationId,
      );

      if (convResult is WordDocumentConversionFailed) {
        await _tryAppendEvent(
          documentId: documentId,
          fileId: source.fileId,
          operationId: operationId,
          eventTypeKey: 'copy_failed',
          resultKey: 'failed',
          sourcePath: source.absolutePath,
          errorCode: ManagedCopyError.wordConversionFailed.name,
          messageSafe: convResult.safeMessage,
        );
        return ManagedCopyFailed(
          error: ManagedCopyError.wordConversionFailed,
          safeMessage:
              'Word document conversion failed: ${convResult.safeMessage}',
        );
      }

      final conv = convResult as WordDocumentConversionSuccess;
      wordTempDir = candidateWordTempDir;
      wordTempPdfPath = conv.tempPdfPath;
      docTrustedHash = conv.pdfSha256;
    }

    try {
      // ── 6. Allocate (or reuse) document code ────────────────────────────────
      // Only reached once a .doc source has been verified-converted (or the
      // source was already a .pdf). A failed conversion above returns before
      // this point, so document_code is never touched by a failed attempt.

      final String docCode;
      try {
        docCode = await _repository.allocateDocumentCode(documentId);
      } on StateError {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.codeSpaceExhausted,
          safeMessage: 'All document code slots are exhausted.',
        );
      }

      // Validate the returned code: must be exactly DOC-[0-9]{7}.
      // This catches malformed values in existing DB rows and any future
      // format drift before the code becomes part of a filesystem path.
      if (!RegExp(r'^DOC-[0-9]{7}$').hasMatch(docCode)) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.malformedDocumentCode,
          safeMessage: 'Allocated document code has an invalid format.',
        );
      }

      // ── Ensure managed files subdirectory exists ────────────────────────────

      final FilesystemOperationResult ensureResult = await _filesystem
          .ensureDirectoryExists(managedFilesDir);
      if (ensureResult is FilesystemFailure) {
        return ManagedCopyFailed(
          error: ManagedCopyError.copyFailed,
          safeMessage:
              'Failed to create managed files directory: ${ensureResult.safeMessage}',
        );
      }

      // Re-resolve the files directory after creation. This closes the gap
      // where a junction/reparse point could appear between the initial
      // validation and directory creation. No backup or managed bytes are
      // written before this second validation succeeds.
      final String? postCreateCanonFiles = _pathCanonicalizer.canonicalize(
        managedFilesDir,
      );
      if (postCreateCanonFiles == null ||
          _normalizePath(postCreateCanonFiles) !=
              _normalizePath(canonFilesDir) ||
          _pathsOverlap(postCreateCanonFiles, canonBackupRoot) ||
          _pathsOverlap(postCreateCanonFiles, canonDatabaseRoot) ||
          canonicalSourceParents.any(
            (sourceParent) => _pathsOverlap(postCreateCanonFiles, sourceParent),
          )) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.unsafeRoots,
          safeMessage:
              'Managed files directory changed or overlaps a protected location.',
        );
      }

      // ── 7. Copy, verify, and finalize ─────────────────────────────────────
      //
      // For .pdf sources the trusted hash is resolved (or reused) inside
      // _executeAfterTempSetup. For .doc sources it was already computed above
      // by the verified Word conversion.

      final String finalPath = _pathJoin(managedFilesDir, '$docCode.pdf');
      final String tmpPath = _pathJoin(
        managedFilesDir,
        '$docCode.pdf.$operationId.copying',
      );

      return await _executeAfterTempSetup(
        documentId: documentId,
        source: source,
        isDocSource: isDocSource,
        operationId: operationId,
        now: now,
        managedFilesDir: managedFilesDir,
        postCreateCanonFiles: postCreateCanonFiles,
        backupRoot: backupRoot,
        finalPath: finalPath,
        tmpPath: tmpPath,
        docCode: docCode,
        docTempPdfPath: wordTempPdfPath.isEmpty ? null : wordTempPdfPath,
        docTrustedHash: docTrustedHash,
      );
    } finally {
      if (wordTempPdfPath.isNotEmpty && wordTempDir.isNotEmpty) {
        await _wordConverter?.cleanupSafely(wordTempPdfPath, wordTempDir);
      }
    }
  }

  Future<ManagedCopyResult> _executeAfterTempSetup({
    required int documentId,
    required SourceFileCandidate source,
    required bool isDocSource,
    required String operationId,
    required DateTime now,
    required String managedFilesDir,
    required String postCreateCanonFiles,
    required String backupRoot,
    required String finalPath,
    required String tmpPath,
    required String docCode,
    required String? docTempPdfPath,
    required String? docTrustedHash,
  }) async {
    // The effective copy source for byte operations.
    // For .pdf sources this is source.absolutePath.
    // For .doc sources this is the temp PDF produced by the earlier verified
    // Word conversion (see execute()).
    final String copySrcPath;
    final String trustedSourceHash;

    if (isDocSource) {
      copySrcPath = docTempPdfPath!;
      trustedSourceHash = docTrustedHash!;
    } else {
      // ── 6b. PDF source hash ─────────────────────────────────────────────────
      // Compute the trusted source hash before artifact detection. This lets us
      // safely recognize a restored final managed file and repair the missing
      // DB row before the conservative artifact guard stops the copy flow.
      if (source.sha256Hash != null) {
        trustedSourceHash = source.sha256Hash!;
      } else {
        final sourceHashResult = await _hasher.hashFile(source.absolutePath);
        if (!sourceHashResult.isSuccess) {
          await _tryAppendEvent(
            documentId: documentId,
            fileId: source.fileId,
            operationId: operationId,
            eventTypeKey: 'copy_failed',
            resultKey: 'failed',
            errorCode: ManagedCopyError.hashFailed.name,
            messageSafe: 'Source file hash computation failed.',
          );
          return const ManagedCopyFailed(
            error: ManagedCopyError.hashFailed,
            safeMessage: 'Source file hash computation failed.',
          );
        }
        trustedSourceHash = sourceHashResult.hash!;
      }
      copySrcPath = source.absolutePath;
    }

    if (_filesystem.isExistingFile(finalPath)) {
      final restored = await _tryRestoreExistingFinalManagedCopy(
        documentId: documentId,
        finalPath: finalPath,
        trustedSourceHash: trustedSourceHash,
        operationId: operationId,
        now: now,
      );
      if (restored == _RestoreManagedFileResult.restored) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.restoredFromDisk,
          safeMessage: 'Missing managed copy found on disk and restored.',
        );
      }
      if (restored == _RestoreManagedFileResult.failed) {
        await _tryAppendEvent(
          documentId: documentId,
          fileId: null,
          operationId: operationId,
          eventTypeKey: 'copy_failed',
          resultKey: 'failed',
          destinationPath: finalPath,
          errorCode: ManagedCopyError.unexpectedFailure.name,
          messageSafe: 'Existing managed copy could not be reconciled safely.',
        );
        return const ManagedCopyFailed(
          error: ManagedCopyError.unexpectedFailure,
          safeMessage: 'Existing managed copy could not be reconciled safely.',
        );
      }
    }

    // Existing strict MARJIY-owned artifacts indicate an interrupted copy or a
    // finalized-but-unregistered file. Never delete or alter them
    // automatically; require later explicit reconciliation.
    final recoveryArtifacts = await _filesystem.findRecoveryArtifacts(
      managedFilesDir,
      docCode,
    );
    if (recoveryArtifacts == null) {
      return const ManagedCopyBlocked(
        error: ManagedCopyError.unsafeRoots,
        safeMessage: 'Managed files directory could not be inspected safely.',
      );
    }
    for (final artifact in recoveryArtifacts) {
      final canonicalArtifact = _pathCanonicalizer.canonicalize(artifact);
      if (canonicalArtifact == null ||
          !_pathIsInsideOrEquals(canonicalArtifact, postCreateCanonFiles)) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.unsafeRoots,
          safeMessage: 'A managed-copy artifact could not be validated safely.',
        );
      }
    }
    if (recoveryArtifacts.isNotEmpty) {
      return ManagedCopyRecoveryRequired(
        verifiedPath: recoveryArtifacts.first,
        safeMessage:
            'An existing MARJIY-managed copy artifact requires reconciliation.',
      );
    }

    final BackupResult backupResult = await _backupService.createBackup(
      backupRoot: backupRoot,
      operationId: operationId,
      timestamp: now,
    );

    if (backupResult is BackupFailure) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: null,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        errorCode: ManagedCopyError.backupFailed.name,
        messageSafe: 'Pre-copy backup failed.',
      );
      return ManagedCopyFailed(
        error: ManagedCopyError.backupFailed,
        safeMessage: 'Pre-copy backup failed: ${(backupResult).safeMessage}',
      );
    }

    // Mandatory: the backup_created event must be committed before any bytes
    // are written. If this write fails, block the copy entirely.
    try {
      await _repository.appendFileEvent(
        documentId: documentId,
        fileId: null,
        eventTypeKey: 'backup_created',
        operationId: operationId,
        resultKey: 'succeeded',
        destinationPath: (backupResult as BackupSuccess).backupPath,
        messageSafe: 'Pre-copy database backup created.',
      );
    } catch (_) {
      return const ManagedCopyFailed(
        error: ManagedCopyError.auditEventFailed,
        safeMessage:
            'Required backup audit event could not be persisted. Copy blocked.',
      );
    }

    // ── Copy, verify, and finalize ────────────────────────────────────────────

    if (_filesystem.isExistingFile(finalPath)) {
      final restored = await _tryRestoreExistingFinalManagedCopy(
        documentId: documentId,
        finalPath: finalPath,
        trustedSourceHash: trustedSourceHash,
        operationId: operationId,
        now: now,
      );
      if (restored == _RestoreManagedFileResult.restored) {
        return const ManagedCopyBlocked(
          error: ManagedCopyError.restoredFromDisk,
          safeMessage: 'Missing managed copy found on disk and restored.',
        );
      }
      if (restored == _RestoreManagedFileResult.failed) {
        await _tryAppendEvent(
          documentId: documentId,
          fileId: null,
          operationId: operationId,
          eventTypeKey: 'copy_failed',
          resultKey: 'failed',
          destinationPath: finalPath,
          errorCode: ManagedCopyError.unexpectedFailure.name,
          messageSafe: 'Existing managed copy could not be reconciled safely.',
        );
        return const ManagedCopyFailed(
          error: ManagedCopyError.unexpectedFailure,
          safeMessage: 'Existing managed copy could not be reconciled safely.',
        );
      }
      // The file at the managed path cannot be verified against the stored hash
      // or the source hash. A database backup was already created, so it is safe
      // to remove this conflicting file and proceed with a fresh, verified copy.
      final deleteResult = await _filesystem.deleteFile(finalPath);
      if (deleteResult is FilesystemFailure) {
        await _tryAppendEvent(
          documentId: documentId,
          fileId: null,
          operationId: operationId,
          eventTypeKey: 'copy_failed',
          resultKey: 'failed',
          destinationPath: finalPath,
          errorCode: ManagedCopyError.targetConflict.name,
          messageSafe:
              'Conflicting managed copy file could not be removed for replacement.',
        );
        return const ManagedCopyFailed(
          error: ManagedCopyError.targetConflict,
          safeMessage:
              'Conflicting managed copy file could not be removed for replacement.',
        );
      }
      await _tryAppendEvent(
        documentId: documentId,
        fileId: null,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'warning',
        destinationPath: finalPath,
        errorCode: ManagedCopyError.targetConflict.name,
        messageSafe:
            'Conflicting managed copy file removed; proceeding with fresh copy.',
      );
      // Fall through — the copy flow below will write the correct verified file.
    }
    if (_filesystem.isExistingFile(tmpPath)) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: null,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        errorCode: ManagedCopyError.temporaryTargetConflict.name,
        messageSafe: 'Temporary copy target already exists.',
      );
      return const ManagedCopyFailed(
        error: ManagedCopyError.temporaryTargetConflict,
        safeMessage: 'Temporary copy target already exists.',
      );
    }

    // Mandatory: the copy_started event must be committed before reading or
    // writing any bytes. If this write fails, block the copy entirely.
    try {
      await _repository.appendFileEvent(
        documentId: documentId,
        fileId: source.fileId,
        eventTypeKey: 'copy_started',
        operationId: operationId,
        resultKey: 'started',
        sourcePath: source.absolutePath,
        destinationPath: tmpPath,
      );
    } catch (_) {
      return const ManagedCopyFailed(
        error: ManagedCopyError.auditEventFailed,
        safeMessage:
            'Required copy-start audit event could not be persisted. Copy blocked.',
      );
    }

    final FilesystemOperationResult copyResult = await _filesystem.copyFile(
      copySrcPath,
      tmpPath,
    );
    if (copyResult is FilesystemFailure) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: source.fileId,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        sourcePath: copySrcPath,
        destinationPath: tmpPath,
        errorCode: ManagedCopyError.copyFailed.name,
        messageSafe: 'Byte copy to temporary target failed.',
      );
      return ManagedCopyFailed(
        error: ManagedCopyError.copyFailed,
        safeMessage: 'Byte copy failed: ${copyResult.safeMessage}',
      );
    }

    // Hash the temporary copy.
    final tmpHashResult = await _hasher.hashFile(tmpPath);
    if (!tmpHashResult.isSuccess) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: source.fileId,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        errorCode: ManagedCopyError.hashFailed.name,
        messageSafe: 'Temporary copy hash computation failed.',
      );
      return const ManagedCopyFailed(
        error: ManagedCopyError.hashFailed,
        safeMessage: 'Copy hash computation failed.',
      );
    }

    if (tmpHashResult.hash! != trustedSourceHash) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: source.fileId,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        expectedSha256: trustedSourceHash,
        actualSha256: tmpHashResult.hash!,
        errorCode: ManagedCopyError.hashMismatch.name,
        messageSafe: 'Copy hash does not match source.',
      );
      return const ManagedCopyFailed(
        error: ManagedCopyError.hashMismatch,
        safeMessage: 'Copy integrity check failed: hash mismatch.',
      );
    }

    // Atomically rename temporary file to the final managed path.
    final FilesystemOperationResult finalizeResult = await _filesystem
        .finalizeFile(tmpPath, finalPath);
    if (finalizeResult is FilesystemFailure) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: source.fileId,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        errorCode: ManagedCopyError.finalizationFailed.name,
        messageSafe: 'File finalization (rename) failed.',
      );
      return ManagedCopyFailed(
        error: ManagedCopyError.finalizationFailed,
        safeMessage: 'File finalization failed: ${finalizeResult.safeMessage}',
      );
    }

    // Read final file size. A null result means the filesystem could not report
    // the size; a zero result means the file is unexpectedly empty. In either
    // case we must not persist a managed-copy record with an unknown or
    // impossible file size.
    final int? rawFileSize = await _filesystem.fileSize(finalPath);
    if (rawFileSize == null) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: null,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        destinationPath: finalPath,
        errorCode: ManagedCopyError.fileSizeUnreadable.name,
        messageSafe: 'Finalized file size could not be read.',
      );
      return ManagedCopyRecoveryRequired(
        verifiedPath: finalPath,
        safeMessage:
            'Copy verified and finalized but file size could not be read. '
            'Recovery is required.',
      );
    }
    if (rawFileSize == 0) {
      await _tryAppendEvent(
        documentId: documentId,
        fileId: null,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        destinationPath: finalPath,
        errorCode: ManagedCopyError.copyFailed.name,
        messageSafe: 'Finalized managed copy has zero bytes.',
      );
      return ManagedCopyRecoveryRequired(
        verifiedPath: finalPath,
        safeMessage:
            'Finalized managed copy has zero bytes. Recovery is required.',
      );
    }

    // ── 7. Transactional success persistence ──────────────────────────────────

    final ManagedCopyPersistenceData persistenceData =
        ManagedCopyPersistenceData(
          documentId: documentId,
          documentCode: docCode,
          operationId: operationId,
          managedFilePath: finalPath,
          managedFileName: '$docCode.pdf',
          sha256Hash: tmpHashResult.hash!,
          fileSizeBytes: rawFileSize,
          sourceFileId: source.fileId,
          sourceFilePath: source.absolutePath,
          nowUtc: now,
        );

    try {
      final int newFileId = await _repository.persistManagedCopySuccess(
        persistenceData,
      );
      return ManagedCopySuccess(
        documentFileId: newFileId,
        documentCode: docCode,
        managedPath: finalPath,
        sha256Hash: tmpHashResult.hash!,
      );
    } catch (_) {
      // File is finalized and verified; DB write failed. Preserve the file for
      // M11 reconciliation. Do not delete or modify it.
      await _tryAppendEvent(
        documentId: documentId,
        fileId: null,
        operationId: operationId,
        eventTypeKey: 'copy_failed',
        resultKey: 'failed',
        destinationPath: finalPath,
        errorCode: ManagedCopyError.databasePersistenceFailed.name,
        messageSafe: 'Database persistence failed after file finalization.',
      );
      return ManagedCopyRecoveryRequired(
        verifiedPath: finalPath,
        safeMessage:
            'Copy file verified and finalized but database persistence failed. '
            'Recovery is required.',
      );
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  bool _isEligibleCandidate(SourceFileCandidate c) {
    final ext = c.storedExtension.toLowerCase();
    return c.fileHealthKey == 'healthy' && (ext == '.pdf' || ext == '.doc');
  }

  SourceFileCandidate? _selectSource(List<SourceFileCandidate> eligible) {
    if (eligible.length == 1) return eligible.first;
    // Prefer PDF sources over .doc to avoid unnecessary conversion.
    final pdfSources = eligible
        .where((c) => c.storedExtension.toLowerCase() == '.pdf')
        .toList();
    if (pdfSources.length == 1) return pdfSources.first;
    if (pdfSources.isEmpty) {
      // Only .doc sources present.
      final preferred = eligible.where((c) => c.isPreferred).toList();
      if (preferred.length == 1) return preferred.first;
      return null;
    }
    // Multiple PDF sources: fall back to isPreferred tie-break.
    final preferred = pdfSources.where((c) => c.isPreferred).toList();
    if (preferred.length == 1) return preferred.first;
    return null;
  }

  Future<_ManagedCopyReconciliation> _reconcileManagedCopyFiles({
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    final managedFiles = await _repository.loadManagedCopyFiles(documentId);
    if (managedFiles.isEmpty) {
      return const _ManagedCopyReconciliation.unchanged();
    }

    final nonMissing = managedFiles
        .where((file) => file.fileHealthKey != 'missing')
        .toList();

    var anyRestored = false;
    for (final missing in managedFiles.where(
      (file) => file.fileHealthKey == 'missing',
    )) {
      final restored = await _tryRestoreMissingManagedFile(
        documentId: documentId,
        fileId: missing.fileId,
        absolutePath: missing.absolutePath,
        fileSizeBytes: missing.fileSizeBytes,
        sha256Hash: missing.sha256Hash,
        operationId: operationId,
        now: now,
      );
      if (restored == _RestoreManagedFileResult.failed) {
        return const _ManagedCopyReconciliation.failed();
      }
      if (restored == _RestoreManagedFileResult.restored) {
        anyRestored = true;
      }
    }

    if (nonMissing.isEmpty) {
      if (anyRestored) {
        return const _ManagedCopyReconciliation.changed(restored: true);
      }
      try {
        await _repository.downgradeDocumentToClassified(
          documentId: documentId,
          now: now,
        );
        return const _ManagedCopyReconciliation.changed();
      } catch (_) {
        return const _ManagedCopyReconciliation.failed();
      }
    }

    var anyMissing = false;
    var anyPresent = false;

    for (final managed in nonMissing) {
      if (_filesystem.isExistingFile(managed.absolutePath)) {
        anyPresent = true;
        continue;
      }

      try {
        await _repository.markManagedFileMissing(
          fileId: managed.fileId,
          documentId: documentId,
          operationId: operationId,
          now: now,
        );
        anyMissing = true;
      } catch (_) {
        return const _ManagedCopyReconciliation.failed();
      }
    }

    if (anyMissing && !anyPresent) {
      try {
        await _repository.downgradeDocumentToClassified(
          documentId: documentId,
          now: now,
        );
      } catch (_) {
        return const _ManagedCopyReconciliation.failed();
      }
    }

    if (anyRestored) {
      return const _ManagedCopyReconciliation.changed(restored: true);
    }
    return anyMissing
        ? const _ManagedCopyReconciliation.changed()
        : const _ManagedCopyReconciliation.unchanged();
  }

  Future<_RestoreManagedFileResult> _tryRestoreMissingManagedFile({
    required int documentId,
    required int fileId,
    required String absolutePath,
    required int fileSizeBytes,
    required String? sha256Hash,
    required String operationId,
    required DateTime now,
  }) async {
    if (!_filesystem.isExistingFile(absolutePath)) {
      return _RestoreManagedFileResult.notRestored;
    }
    if (sha256Hash == null || sha256Hash.isEmpty) {
      return _RestoreManagedFileResult.notRestored;
    }

    final size = await _filesystem.fileSize(absolutePath);
    if (size == null || size != fileSizeBytes) {
      return _RestoreManagedFileResult.notRestored;
    }

    final hash = await _hasher.hashFile(absolutePath);
    if (!hash.isSuccess || hash.hash != sha256Hash) {
      return _RestoreManagedFileResult.notRestored;
    }

    try {
      await _repository.restoreManagedFileHealthy(
        fileId: fileId,
        documentId: documentId,
        operationId: operationId,
        now: now,
      );
    } catch (_) {
      return _RestoreManagedFileResult.failed;
    }

    return _RestoreManagedFileResult.restored;
  }

  Future<_RestoreManagedFileResult> _tryRestoreExistingFinalManagedCopy({
    required int documentId,
    required String finalPath,
    required String trustedSourceHash,
    required String operationId,
    required DateTime now,
  }) async {
    final managedFiles = await _repository.loadManagedCopyFiles(documentId);
    final matchingMissingRows = managedFiles
        .where(
          (file) =>
              file.fileHealthKey == 'missing' &&
              _samePath(file.absolutePath, finalPath),
        )
        .toList(growable: false);
    if (matchingMissingRows.isEmpty) {
      return _RestoreManagedFileResult.notRestored;
    }
    if (matchingMissingRows.length > 1) {
      return _RestoreManagedFileResult.failed;
    }

    final missing = matchingMissingRows.single;
    final size = await _filesystem.fileSize(finalPath);
    if (size == null || size <= 0 || size != missing.fileSizeBytes) {
      return _RestoreManagedFileResult.notRestored;
    }

    final storedHash = missing.sha256Hash;
    if (storedHash == null || storedHash.isEmpty) {
      return _RestoreManagedFileResult.notRestored;
    }

    final hash = await _hasher.hashFile(finalPath);
    if (!hash.isSuccess ||
        hash.hash != storedHash ||
        hash.hash != trustedSourceHash) {
      return _RestoreManagedFileResult.notRestored;
    }

    try {
      await _repository.restoreManagedFileHealthy(
        fileId: missing.fileId,
        documentId: documentId,
        operationId: operationId,
        now: now,
      );
    } catch (_) {
      return _RestoreManagedFileResult.failed;
    }

    return _RestoreManagedFileResult.restored;
  }

  static bool _isAbsolutePath(String path) =>
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);

  /// Lowercases and normalizes separators for case-insensitive comparison.
  static String _normalizePath(String path) {
    var result = path.replaceAll('/', r'\').toLowerCase();
    while (result.length > 3 && result.endsWith(r'\')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// True when [inner] is equal to [outer] or is a descendant of [outer].
  static bool _pathIsInsideOrEquals(String inner, String outer) {
    final normInner = _normalizePath(inner);
    final normOuter = _normalizePath(outer);
    if (normInner == normOuter) return true;
    // normOuter already ends with '\' when it is a drive root (e.g. 'c:\').
    // Avoid doubling the separator so 'c:\data'.startsWith('c:\') works
    // correctly instead of checking the impossible 'c:\\'.
    final prefix = normOuter.endsWith(r'\') ? normOuter : '$normOuter\\';
    return normInner.startsWith(prefix);
  }

  static bool _pathsOverlap(String first, String second) =>
      _pathIsInsideOrEquals(first, second) ||
      _pathIsInsideOrEquals(second, first);

  static bool _samePath(String first, String second) =>
      _normalizePath(first) == _normalizePath(second);

  /// Joins two path segments with a Windows backslash separator.
  static String _pathJoin(String base, String part) {
    final b = base.replaceAll('/', r'\');
    final trimmed = (b.length > 3 && b.endsWith(r'\'))
        ? b.substring(0, b.length - 1)
        : b;
    return '$trimmed\\$part';
  }

  /// Returns the extension of the last path component (including leading dot).
  static String _pathExtension(String path) {
    final name = path.replaceAll('/', r'\').split(r'\').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }

  /// Returns the parent directory of a file path.
  static String _parentDir(String path) {
    final normalized = path.replaceAll('/', r'\');
    final lastSep = normalized.lastIndexOf(r'\');
    if (lastSep <= 2) return normalized.substring(0, lastSep + 1);
    return normalized.substring(0, lastSep);
  }

  Future<void> _tryAppendEvent({
    required int? documentId,
    required int? fileId,
    required String operationId,
    required String eventTypeKey,
    required String resultKey,
    String? sourcePath,
    String? destinationPath,
    String? expectedSha256,
    String? actualSha256,
    String? errorCode,
    String? messageSafe,
  }) async {
    try {
      await _repository.appendFileEvent(
        documentId: documentId,
        fileId: fileId,
        eventTypeKey: eventTypeKey,
        operationId: operationId,
        resultKey: resultKey,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        expectedSha256: expectedSha256,
        actualSha256: actualSha256,
        errorCode: errorCode,
        messageSafe: messageSafe,
      );
    } catch (_) {
      // Failure events are best-effort; swallow so the primary result is always returned.
    }
  }
}

class _ManagedCopyReconciliation {
  const _ManagedCopyReconciliation._({
    required this.succeeded,
    required this.changed,
    this.anyRestored = false,
  });

  const _ManagedCopyReconciliation.unchanged()
    : this._(succeeded: true, changed: false);

  const _ManagedCopyReconciliation.changed({bool restored = false})
    : this._(succeeded: true, changed: true, anyRestored: restored);

  const _ManagedCopyReconciliation.failed()
    : this._(succeeded: false, changed: false);

  final bool succeeded;
  final bool changed;

  /// True when at least one previously-missing managed-copy file was found
  /// on disk with a matching hash/size and its DB record was restored.
  final bool anyRestored;
}

enum _RestoreManagedFileResult { notRestored, restored, failed }
