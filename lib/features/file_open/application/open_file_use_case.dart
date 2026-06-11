// lib/features/file_open/application/open_file_use_case.dart

import '../domain/entities/file_health_eligibility.dart';
import '../domain/entities/open_file_result.dart';
import '../domain/entities/open_target.dart';
import '../domain/repositories/file_open_repository.dart';
import '../domain/services/file_existence_checker.dart';
import '../domain/services/os_file_opener.dart';

/// Orchestrates the safe-open workflow (spec §7).
///
/// Accepts only a database [fileId] and an explicit [target]. Never accepts
/// an arbitrary path. Never modifies documents, document_files, or workflow
/// statuses. Records every attempt in [file_open_events] where the FK permits.
class OpenFileUseCase {
  const OpenFileUseCase({
    required this._repository,
    required this._existenceChecker,
    required this._osOpener,
  });

  final FileOpenRepository _repository;
  final FileExistenceChecker _existenceChecker;
  final OsFileOpener _osOpener;

  /// MVP allowed extensions (lowercase). Both the stored field and the
  /// extension derived from absolutePath must be in this list and must agree.
  static const List<String> _allowedExtensions = ['.pdf'];

  /// Extracts the file extension (including leading dot) from a Windows or
  /// POSIX absolute path without importing dart:io or dart:path.
  static String _pathExtension(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }

  Future<OpenFileResult> execute(int fileId, OpenTarget target) async {
    // 1. Load the database-backed file record. Only registered IDs may proceed.
    final record = await _repository.loadFileRecord(fileId);
    if (record == null) {
      // The FK constraint on file_open_events.file_id will reject insertion
      // for unknown IDs; _tryRecord swallows the resulting error.
      await _tryRecord(
        fileId: fileId,
        documentId: null,
        target: target,
        resultKey: 'blocked',
        errorCode: FileOpenError.fileRecordNotFound.name,
        messageSafe: 'File record not found in database.',
      );
      return const OpenFileBlocked(
        code: FileOpenError.fileRecordNotFound,
        safeMessage: 'File record not found in database.',
      );
    }

    // 1.5. Block direct file opening for non-healthy files. The folder target
    //      is never restricted by health status, so users can still reach the
    //      containing folder to investigate a corrupted or missing file.
    if (target == OpenTarget.file &&
        !canOpenFileDirectly(record.fileHealthKey)) {
      await _tryRecord(
        fileId: fileId,
        documentId: record.documentId,
        target: target,
        resultKey: 'blocked',
        errorCode: FileOpenError.unhealthyFile.name,
        messageSafe: 'File health status prevents direct opening.',
      );
      return const OpenFileBlocked(
        code: FileOpenError.unhealthyFile,
        safeMessage: 'File health status prevents direct opening.',
      );
    }

    // 2. Reject a blank stored path (data integrity guard).
    if (record.absolutePath.trim().isEmpty) {
      await _tryRecord(
        fileId: fileId,
        documentId: record.documentId,
        target: target,
        resultKey: 'blocked',
        errorCode: FileOpenError.missingPath.name,
        messageSafe: 'Stored file path is empty.',
      );
      return const OpenFileBlocked(
        code: FileOpenError.missingPath,
        safeMessage: 'Stored file path is empty.',
      );
    }

    // 3. Check filesystem existence and type via the injected abstraction.
    final status = _existenceChecker.checkFile(record.absolutePath);
    switch (status) {
      case FileExistenceStatus.notFound:
        await _tryRecord(
          fileId: fileId,
          documentId: record.documentId,
          target: target,
          resultKey: 'blocked',
          errorCode: FileOpenError.pathNotFound.name,
          messageSafe: 'Stored path does not exist on the filesystem.',
        );
        return const OpenFileBlocked(
          code: FileOpenError.pathNotFound,
          safeMessage: 'Stored path does not exist on the filesystem.',
        );
      case FileExistenceStatus.directory:
        await _tryRecord(
          fileId: fileId,
          documentId: record.documentId,
          target: target,
          resultKey: 'blocked',
          errorCode: FileOpenError.notARegularFile.name,
          messageSafe: 'Path resolves to a directory, not a regular file.',
        );
        return const OpenFileBlocked(
          code: FileOpenError.notARegularFile,
          safeMessage: 'Path resolves to a directory, not a regular file.',
        );
      case FileExistenceStatus.accessDenied:
        await _tryRecord(
          fileId: fileId,
          documentId: record.documentId,
          target: target,
          resultKey: 'failed',
          errorCode: FileOpenError.permissionDenied.name,
          messageSafe: 'Access denied when checking the file.',
        );
        return const OpenFileFailed(
          code: FileOpenError.permissionDenied,
          safeMessage: 'Access denied when checking the file.',
        );
      case FileExistenceStatus.regularFile:
        break;
    }

    // 4. Validate both the stored extension and the extension derived from the
    // registered absolutePath. Both must be .pdf (case-insensitive) and they
    // must agree. This guards against stale document_files.extension values
    // and against paths whose actual suffix differs from the stored field.
    final storedExt = record.extension.toLowerCase();
    final actualExt = _pathExtension(record.absolutePath).toLowerCase();

    if (!_allowedExtensions.contains(storedExt) ||
        !_allowedExtensions.contains(actualExt) ||
        storedExt != actualExt) {
      await _tryRecord(
        fileId: fileId,
        documentId: record.documentId,
        target: target,
        resultKey: 'blocked',
        errorCode: FileOpenError.unsupportedExtension.name,
        messageSafe: 'File extension is not in the allowed list.',
      );
      return const OpenFileBlocked(
        code: FileOpenError.unsupportedExtension,
        safeMessage: 'File extension is not in the allowed list.',
      );
    }

    // 5. Delegate to the OS boundary (injected, never a real process in tests).
    final OsOpenResult osResult = target == OpenTarget.file
        ? await _osOpener.openFile(record.absolutePath)
        : await _osOpener.openFolder(record.absolutePath);

    if (osResult is OsOpenFailed) {
      await _tryRecord(
        fileId: fileId,
        documentId: record.documentId,
        target: target,
        resultKey: 'failed',
        errorCode: osResult.code.name,
        messageSafe: osResult.safeMessage,
      );
      return OpenFileFailed(
        code: osResult.code,
        safeMessage: osResult.safeMessage,
      );
    }

    // 6. OS launch succeeded. Record the success event.
    // If persistence itself fails, return an audit-failure result without
    // falsely claiming the OS launch failed.
    try {
      await _repository.recordOpenEvent(
        fileId: fileId,
        documentId: record.documentId,
        target: target,
        resultKey: 'succeeded',
      );
      return OpenFileSuccess(target: target);
    } catch (_) {
      return OpenFileAuditFailure(target: target);
    }
  }

  /// Records an event, swallowing persistence errors so the primary result is
  /// always returned to the caller.
  Future<void> _tryRecord({
    required int fileId,
    required int? documentId,
    required OpenTarget target,
    required String resultKey,
    String? errorCode,
    String? messageSafe,
  }) async {
    try {
      await _repository.recordOpenEvent(
        fileId: fileId,
        documentId: documentId,
        target: target,
        resultKey: resultKey,
        errorCode: errorCode,
        messageSafe: messageSafe,
      );
    } catch (_) {
      // Swallow; the primary result is always delivered to the caller.
    }
  }
}
