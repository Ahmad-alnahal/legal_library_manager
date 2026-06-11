// lib/features/file_open/presentation/bloc/file_open_state.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/open_file_result.dart';
import '../../domain/entities/open_target.dart';

/// Lifecycle of a safe-open request as seen by the UI.
enum FileOpenStatus {
  /// No request in flight and no pending feedback.
  idle,

  /// A request is currently executing for [FileOpenUiState.activeFileId] /
  /// [FileOpenUiState.activeTarget].
  opening,

  /// The OS opened the file/folder and the audit event was recorded.
  success,

  /// A safety check prevented the OS call.
  blocked,

  /// The OS call was attempted but the OS reported failure.
  failed,

  /// The OS opened the file/folder but recording the audit event failed.
  auditFailure,
}

/// Immutable UI state for the safe-open controller.
///
/// Carries only stable, safe data: a lifecycle [status], the active file ID and
/// target (so a single clicked action can show loading), and a stable
/// [FileOpenError] code for failure mapping. It never carries raw exception
/// text, file paths, command strings, or stack traces.
class FileOpenUiState extends Equatable {
  const FileOpenUiState({
    this.status = FileOpenStatus.idle,
    this.activeFileId,
    this.activeTarget,
    this.errorCode,
  });

  final FileOpenStatus status;
  final int? activeFileId;
  final OpenTarget? activeTarget;

  /// Stable error code for [FileOpenStatus.blocked] / [FileOpenStatus.failed].
  /// Null for all other states.
  final FileOpenError? errorCode;

  /// True while any open request is executing.
  bool get isBusy => status == FileOpenStatus.opening;

  /// True when a terminal result is awaiting user feedback.
  bool get isTerminal =>
      status == FileOpenStatus.success ||
      status == FileOpenStatus.blocked ||
      status == FileOpenStatus.failed ||
      status == FileOpenStatus.auditFailure;

  /// True when this exact file/target action is the one currently opening, used
  /// to show a spinner only on the clicked action.
  bool isActive(int fileId, OpenTarget target) =>
      status == FileOpenStatus.opening &&
      activeFileId == fileId &&
      activeTarget == target;

  @override
  List<Object?> get props => [status, activeFileId, activeTarget, errorCode];
}
