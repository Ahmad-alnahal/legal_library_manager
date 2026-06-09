// lib/features/import/presentation/bloc/import_bloc.dart

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/import_coordinator.dart';
import '../../application/import_progress.dart';
import '../../application/import_run_report.dart';
import '../../application/protected_roots_provider.dart';
import '../../domain/entities/import_batch_report.dart';
import '../../domain/entities/import_request.dart';
import '../../domain/services/file_hasher.dart';

part 'import_event.dart';
part 'import_state.dart';

/// Drives the import workflow UI: folder selection, start, live progress,
/// cooperative cancellation, terminal report, and retry/reset.
///
/// The long-running import runs as a detached future that feeds back through
/// private progress/finished events, so the BLoC keeps processing user events
/// (notably cancel) while an import is active. A second start is rejected while
/// one is active, and [close] cancels any in-flight run so nothing hangs.
class ImportBloc extends Bloc<ImportEvent, ImportState> {
  ImportBloc({required this.coordinator, required this.protectedRootsProvider})
    : super(const ImportState()) {
    on<ImportFolderSelected>(_onFolderSelected);
    on<ImportRecursiveToggled>(_onRecursiveToggled);
    on<ImportStartRequested>(_onStartRequested);
    on<ImportCancelRequested>(_onCancelRequested);
    on<ImportRetryRequested>(_onRetryRequested);
    on<ImportResetRequested>(_onResetRequested);
    on<ImportProgressed>(_onProgressed);
    on<ImportFinished>(_onFinished);
    on<ImportFailedInternally>(_onFailedInternally);
  }

  final ImportCoordinator coordinator;
  final ProtectedRootsProvider protectedRootsProvider;

  MutableHashCancellation? _cancellation;

  /// The currently running import or retry future. Tracked so [close] can
  /// await its settlement, ensuring no detached repository work survives after
  /// the BLoC is disposed.
  Future<void>? _activeFuture;

  void _onFolderSelected(
    ImportFolderSelected event,
    Emitter<ImportState> emit,
  ) {
    if (state.isActive) return;
    emit(
      state.copyWith(
        status: ImportStatus.idle,
        selectedFolder: event.path,
        clearProgress: true,
        clearReport: true,
      ),
    );
  }

  void _onRecursiveToggled(
    ImportRecursiveToggled event,
    Emitter<ImportState> emit,
  ) {
    if (state.isActive) return;
    emit(state.copyWith(recursive: event.recursive));
  }

  void _onStartRequested(
    ImportStartRequested event,
    Emitter<ImportState> emit,
  ) {
    if (state.isActive) return;
    final String? folder = state.selectedFolder;
    if (folder == null || folder.trim().isEmpty) return;

    final MutableHashCancellation cancellation = MutableHashCancellation();
    _cancellation = cancellation;
    emit(
      state.copyWith(
        status: ImportStatus.validating,
        clearProgress: true,
        clearReport: true,
      ),
    );
    _activeFuture = _runImport(folder, state.recursive, cancellation)
        .whenComplete(() {
          _activeFuture = null;
        });
  }

  void _onRetryRequested(
    ImportRetryRequested event,
    Emitter<ImportState> emit,
  ) {
    if (state.isActive) return;
    final ImportRunReport? previous = state.report;
    if (previous == null || !previous.hasRetryableFailures) return;

    final MutableHashCancellation cancellation = MutableHashCancellation();
    _cancellation = cancellation;
    emit(state.copyWith(status: ImportStatus.importing));
    _activeFuture = _runRetry(previous, cancellation).whenComplete(() {
      _activeFuture = null;
    });
  }

  void _onCancelRequested(
    ImportCancelRequested event,
    Emitter<ImportState> emit,
  ) {
    if (!state.isActive) return;
    _cancellation?.cancel();
    emit(state.copyWith(status: ImportStatus.cancelling));
  }

  void _onResetRequested(
    ImportResetRequested event,
    Emitter<ImportState> emit,
  ) {
    if (state.isActive) return;
    emit(
      ImportState(
        selectedFolder: state.selectedFolder,
        recursive: state.recursive,
      ),
    );
  }

  void _onProgressed(ImportProgressed event, Emitter<ImportState> emit) {
    if (!state.isActive) return;
    // While cancelling, keep the cancelling status but reflect latest progress.
    if (state.status == ImportStatus.cancelling) {
      emit(state.copyWith(progress: event.progress));
      return;
    }
    emit(
      state.copyWith(
        status: _statusForPhase(event.progress.phase),
        progress: event.progress,
      ),
    );
  }

  void _onFinished(ImportFinished event, Emitter<ImportState> emit) {
    _cancellation = null;
    final ImportRunReport report = event.report;
    final ImportStatus status = switch (report.status) {
      ImportBatchStatus.completed => ImportStatus.completed,
      ImportBatchStatus.cancelled => ImportStatus.cancelled,
      ImportBatchStatus.failed => ImportStatus.failed,
      // A terminal report should never still be "running"; treat it as a safe
      // failure rather than silently reporting success.
      ImportBatchStatus.running => ImportStatus.failed,
    };
    emit(state.copyWith(status: status, report: report, clearProgress: true));
  }

  void _onFailedInternally(
    ImportFailedInternally event,
    Emitter<ImportState> emit,
  ) {
    _cancellation = null;
    emit(state.copyWith(status: ImportStatus.failed, clearProgress: true));
  }

  Future<void> _runImport(
    String folder,
    bool recursive,
    MutableHashCancellation cancellation,
  ) async {
    try {
      final ImportRequest request = ImportRequest(
        sourceFolder: folder,
        recursive: recursive,
        protectedRoots: await protectedRootsProvider.load(),
      );
      final ImportRunReport report = await coordinator.run(
        request,
        cancellation: cancellation,
        onProgress: _emitProgress,
      );
      if (!isClosed) add(ImportFinished(report));
    } catch (_) {
      if (!isClosed) add(const ImportFailedInternally());
    }
  }

  Future<void> _runRetry(
    ImportRunReport previous,
    MutableHashCancellation cancellation,
  ) async {
    try {
      final ImportRunReport report = await coordinator.retry(
        previous,
        cancellation: cancellation,
        onProgress: _emitProgress,
      );
      if (!isClosed) add(ImportFinished(report));
    } catch (_) {
      if (!isClosed) add(const ImportFailedInternally());
    }
  }

  void _emitProgress(ImportProgress progress) {
    if (!isClosed) add(ImportProgressed(progress));
  }

  static ImportStatus _statusForPhase(ImportPhase phase) {
    return switch (phase) {
      ImportPhase.validating => ImportStatus.validating,
      ImportPhase.scanning => ImportStatus.scanning,
      ImportPhase.importing => ImportStatus.importing,
      ImportPhase.finalizing => ImportStatus.importing,
    };
  }

  @override
  Future<void> close() {
    _cancellation?.cancel();
    _cancellation = null;
    final superFuture = super.close();
    final active = _activeFuture;
    _activeFuture = null;
    if (active == null) return superFuture;
    // Wait for both the BLoC event stream to close AND the active run to
    // settle. After super.close(), isClosed is true, so the run's final
    // add(ImportFinished) is already guarded and will not execute.
    // active errors are swallowed: they are internal, already-handled failures.
    return Future.wait([superFuture, active.then((_) {}, onError: (_) {})]);
  }
}
