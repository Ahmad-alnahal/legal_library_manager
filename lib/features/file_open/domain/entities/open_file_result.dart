// lib/features/file_open/domain/entities/open_file_result.dart

import 'open_target.dart';

/// Stable error codes for safe-open failures.
///
/// The [name] of each variant is persisted to [file_open_events.error_code]
/// and must remain stable so Arabic UI strings can be mapped without coupling
/// to the persistence layer.
enum FileOpenError {
  /// No [document_files] row exists for the requested ID.
  fileRecordNotFound,

  /// The stored [absolute_path] is empty or blank.
  missingPath,

  /// The stored path does not exist on the filesystem.
  pathNotFound,

  /// The stored path resolves to a directory, not a regular file.
  notARegularFile,

  /// The file's extension is not in the MVP allowed list.
  unsupportedExtension,

  /// The OS or filesystem denied access to the file.
  permissionDenied,

  /// No Windows application is registered for the file type.
  noAssociatedApplication,

  /// The OS failed to launch the associated application.
  osLaunchFailed,

  /// The OS launch succeeded but recording the audit event in the database
  /// subsequently failed.
  eventPersistenceFailed,

  /// The file's [file_health_status_key] is not 'healthy'. Only files with a
  /// 'healthy' status may be opened directly. The containing folder may still
  /// be revealed via [OpenTarget.folder].
  unhealthyFile,
}

/// Result of a safe-open attempt. Never carries command strings, stack
/// traces, document contents, or raw exception messages.
sealed class OpenFileResult {
  const OpenFileResult();
}

/// The OS launched the file or folder and the event was recorded.
final class OpenFileSuccess extends OpenFileResult {
  const OpenFileSuccess({required this.target});
  final OpenTarget target;
}

/// The OS launched the file or folder, but the subsequent audit-event
/// persistence failed. The file was opened; only the audit trail is
/// incomplete. This is not an OS failure.
final class OpenFileAuditFailure extends OpenFileResult {
  const OpenFileAuditFailure({required this.target});
  final OpenTarget target;
}

/// A safety check prevented the OS call from being made. The event was
/// recorded (where the FK permits) with [result_key] = 'blocked'.
final class OpenFileBlocked extends OpenFileResult {
  const OpenFileBlocked({required this.code, required this.safeMessage});
  final FileOpenError code;
  final String safeMessage;
}

/// The OS call was attempted but the OS reported failure. The event was
/// recorded with [result_key] = 'failed'.
final class OpenFileFailed extends OpenFileResult {
  const OpenFileFailed({required this.code, required this.safeMessage});
  final FileOpenError code;
  final String safeMessage;
}
