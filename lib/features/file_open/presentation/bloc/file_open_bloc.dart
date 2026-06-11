// lib/features/file_open/presentation/bloc/file_open_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/open_file_use_case.dart';
import '../../domain/entities/open_file_result.dart';
import '../../domain/entities/open_target.dart';
import 'file_open_event.dart';
import 'file_open_state.dart';

/// Presentation controller for safe file/folder opening.
///
/// This is the only presentation boundary permitted to drive [OpenFileUseCase].
/// It depends on nothing else: no Drift, no filesystem I/O, no process or Win32 APIs.
/// It accepts only a registered database file ID and an [OpenTarget], tracks the
/// active action so only the clicked control shows loading, drops overlapping
/// requests while one open is in flight, and ignores rapid duplicate requests
/// for the same file+target within a 1-second cooldown.
class FileOpenBloc extends Bloc<FileOpenEvent, FileOpenUiState> {
  FileOpenBloc(this._useCase, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const FileOpenUiState()) {
    on<FileOpenRequested>(_onRequested);
    on<FileOpenFeedbackHandled>(_onFeedbackHandled);
  }

  final OpenFileUseCase _useCase;
  final DateTime Function() _clock;

  /// Synchronous guard set before the first `await`, so two rapid taps cannot
  /// both pass the in-flight check regardless of the event transformer.
  bool _inFlight = false;

  /// Records the most recent accepted timestamp per (fileId, target) key.
  /// Requests for the same key arriving within [_cooldown] are silently dropped
  /// without invoking the use case, preventing rapid repeated OS launches
  /// (e.g. multiple Explorer windows) while still allowing the action to be
  /// used again after the cooldown expires.
  final Map<(int, OpenTarget), DateTime> _lastAccepted = {};

  static const Duration _cooldown = Duration(seconds: 1);

  Future<void> _onRequested(
    FileOpenRequested event,
    Emitter<FileOpenUiState> emit,
  ) async {
    if (_inFlight) return; // Drop overlapping requests.

    // Cooldown guard: ignore identical (fileId, target) requests accepted less
    // than 1 second ago. No audit record is created for dropped duplicates.
    final key = (event.fileId, event.target);
    final last = _lastAccepted[key];
    if (last != null && _clock().difference(last) < _cooldown) return;
    _lastAccepted[key] = _clock();

    _inFlight = true;
    emit(
      FileOpenUiState(
        status: FileOpenStatus.opening,
        activeFileId: event.fileId,
        activeTarget: event.target,
      ),
    );
    try {
      final result = await _useCase.execute(event.fileId, event.target);
      emit(_mapResult(result, event.fileId, event.target));
    } catch (_) {
      // The use case is designed never to throw; this is a defensive fallback
      // so an unexpected error cannot leave the UI stuck in a loading state.
      // No raw error detail is surfaced — only a stable, safe code.
      emit(
        FileOpenUiState(
          status: FileOpenStatus.failed,
          activeFileId: event.fileId,
          activeTarget: event.target,
          errorCode: FileOpenError.osLaunchFailed,
        ),
      );
    } finally {
      _inFlight = false;
    }
  }

  void _onFeedbackHandled(
    FileOpenFeedbackHandled event,
    Emitter<FileOpenUiState> emit,
  ) {
    // Only reset terminal states; never interrupt an in-flight open.
    if (state.status == FileOpenStatus.opening) return;
    emit(const FileOpenUiState());
  }

  FileOpenUiState _mapResult(
    OpenFileResult result,
    int fileId,
    OpenTarget target,
  ) {
    return switch (result) {
      OpenFileSuccess(:final target) => FileOpenUiState(
        status: FileOpenStatus.success,
        activeFileId: fileId,
        activeTarget: target,
      ),
      OpenFileAuditFailure(:final target) => FileOpenUiState(
        status: FileOpenStatus.auditFailure,
        activeFileId: fileId,
        activeTarget: target,
      ),
      OpenFileBlocked(:final code) => FileOpenUiState(
        status: FileOpenStatus.blocked,
        activeFileId: fileId,
        activeTarget: target,
        errorCode: code,
      ),
      OpenFileFailed(:final code) => FileOpenUiState(
        status: FileOpenStatus.failed,
        activeFileId: fileId,
        activeTarget: target,
        errorCode: code,
      ),
    };
  }
}
