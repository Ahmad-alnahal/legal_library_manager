// lib/features/import/presentation/bloc/import_bloc.dart

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/import_job_service.dart';
import '../../application/import_job_snapshot.dart';
import '../../application/import_progress.dart';
import '../../application/import_run_report.dart';

part 'import_event.dart';
part 'import_state.dart';

/// Drives the import workflow UI by subscribing to [ImportJobService].
///
/// User events (folder selection, start, cancel, retry, reset) are forwarded to
/// the service. State updates arrive through the service's broadcast stream,
/// translated into BLoC states. The job survives BLoC disposal — closing this
/// BLoC cancels the subscription but never stops the running import.
class ImportBloc extends Bloc<ImportEvent, ImportState> {
  ImportBloc({required this.jobService})
    : super(_stateFromSnapshot(jobService.current)) {
    on<ImportFolderSelected>(_onFolderSelected);
    on<ImportRecursiveToggled>(_onRecursiveToggled);
    on<ImportStartRequested>(_onStartRequested);
    on<ImportCancelRequested>(_onCancelRequested);
    on<ImportRetryRequested>(_onRetryRequested);
    on<ImportResetRequested>(_onResetRequested);
    on<ImportJobSnapshotReceived>(_onSnapshotReceived);

    _sub = jobService.snapshots.listen((ImportJobSnapshot snap) {
      if (!isClosed) add(ImportJobSnapshotReceived(snap));
    });
  }

  final ImportJobService jobService;
  StreamSubscription<ImportJobSnapshot>? _sub;

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
    // Emit validating immediately so the UI responds before the first snapshot
    // arrives from the service's async stream delivery.
    emit(
      state.copyWith(
        status: ImportStatus.validating,
        clearProgress: true,
        clearReport: true,
      ),
    );
    jobService.start(folder: folder, recursive: state.recursive);
  }

  void _onCancelRequested(
    ImportCancelRequested event,
    Emitter<ImportState> emit,
  ) {
    if (!state.isActive) return;
    jobService.cancel();
    emit(state.copyWith(status: ImportStatus.cancelling));
  }

  void _onRetryRequested(
    ImportRetryRequested event,
    Emitter<ImportState> emit,
  ) {
    if (state.isActive) return;
    final ImportRunReport? report = state.report;
    if (report == null || !report.hasRetryableFailures) return;
    emit(state.copyWith(status: ImportStatus.importing));
    jobService.retry(report);
  }

  void _onResetRequested(
    ImportResetRequested event,
    Emitter<ImportState> emit,
  ) {
    if (state.isActive) return;
    jobService.reset();
    emit(
      ImportState(
        selectedFolder: state.selectedFolder,
        recursive: state.recursive,
      ),
    );
  }

  void _onSnapshotReceived(
    ImportJobSnapshotReceived event,
    Emitter<ImportState> emit,
  ) {
    final ImportJobSnapshot snap = event.snapshot;
    if (snap.status == ImportJobStatus.idle) {
      emit(
        state.copyWith(
          status: ImportStatus.idle,
          clearProgress: true,
          clearReport: true,
        ),
      );
      return;
    }
    if (snap.isActive) {
      emit(
        state.copyWith(
          status: _importStatusFrom(snap),
          progress: snap.progress,
        ),
      );
      return;
    }
    // Terminal snapshot.
    emit(
      state.copyWith(
        status: _importStatusFrom(snap),
        report: snap.report,
        clearProgress: true,
      ),
    );
  }

  static ImportStatus _importStatusFrom(ImportJobSnapshot snap) {
    return switch (snap.status) {
      ImportJobStatus.idle => ImportStatus.idle,
      ImportJobStatus.running => _phaseToStatus(snap.progress?.phase),
      ImportJobStatus.cancelling => ImportStatus.cancelling,
      ImportJobStatus.completed => ImportStatus.completed,
      ImportJobStatus.cancelled => ImportStatus.cancelled,
      ImportJobStatus.failed => ImportStatus.failed,
    };
  }

  static ImportStatus _phaseToStatus(ImportPhase? phase) {
    return switch (phase) {
      ImportPhase.validating => ImportStatus.validating,
      ImportPhase.scanning => ImportStatus.scanning,
      ImportPhase.importing => ImportStatus.importing,
      ImportPhase.finalizing => ImportStatus.importing,
      null => ImportStatus.importing,
    };
  }

  static ImportState _stateFromSnapshot(ImportJobSnapshot snap) {
    return ImportState(
      status: _importStatusFrom(snap),
      progress: snap.progress,
      report: snap.report,
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _sub = null;
    return super.close();
  }
}
