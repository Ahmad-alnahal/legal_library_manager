// lib/features/file_open/presentation/bloc/file_open_event.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/open_target.dart';

/// Events for the safe-open controller.
sealed class FileOpenEvent extends Equatable {
  const FileOpenEvent();

  @override
  List<Object?> get props => [];
}

/// Requests a safe open of a registered database file.
///
/// Carries only the database [fileId] and the [target]. It never carries a
/// path, so no arbitrary user path can reach the use case through the UI.
class FileOpenRequested extends FileOpenEvent {
  const FileOpenRequested(this.fileId, this.target);

  final int fileId;
  final OpenTarget target;

  @override
  List<Object?> get props => [fileId, target];
}

/// Signals that the terminal-result feedback (e.g. a SnackBar) has been shown,
/// returning the controller to idle so the same result cannot re-trigger a
/// stale message on a later rebuild.
class FileOpenFeedbackHandled extends FileOpenEvent {
  const FileOpenFeedbackHandled();
}
