// lib/features/import/presentation/bloc/import_status_bloc.dart

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/import_job_service.dart';
import '../../application/import_job_snapshot.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class ImportStatusEvent extends Equatable {
  const ImportStatusEvent();
  @override
  List<Object?> get props => const [];
}

class _ImportStatusSnapshotReceived extends ImportStatusEvent {
  const _ImportStatusSnapshotReceived(this.snapshot);
  final ImportJobSnapshot snapshot;
  @override
  List<Object?> get props => [snapshot];
}

/// User requested cancellation of the active import from the global banner.
class ImportStatusCancelRequested extends ImportStatusEvent {
  const ImportStatusCancelRequested();
}

/// User dismissed the terminal result banner.
class ImportStatusDismissRequested extends ImportStatusEvent {
  const ImportStatusDismissRequested();
}

// ── State ─────────────────────────────────────────────────────────────────────

class ImportStatusState extends Equatable {
  const ImportStatusState({required this.snapshot, this.dismissed = false});

  final ImportJobSnapshot snapshot;

  /// True after the user closes a terminal-state banner.
  /// Cleared automatically when any new non-idle snapshot arrives.
  final bool dismissed;

  /// The banner should be visible iff the snapshot is non-idle and not dismissed.
  bool get isVisible => snapshot.status != ImportJobStatus.idle && !dismissed;

  ImportStatusState copyWith({ImportJobSnapshot? snapshot, bool? dismissed}) {
    return ImportStatusState(
      snapshot: snapshot ?? this.snapshot,
      dismissed: dismissed ?? this.dismissed,
    );
  }

  @override
  List<Object?> get props => [snapshot, dismissed];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

/// Lightweight global BLoC that mirrors [ImportJobService] state for the shell.
///
/// Lives for the lifetime of [AppShellPage]. Closing the BLoC cancels the
/// stream subscription but never stops the running import — the service is a
/// GetIt singleton and continues independently.
class ImportStatusBloc extends Bloc<ImportStatusEvent, ImportStatusState> {
  ImportStatusBloc({required ImportJobService jobService})
    : _jobService = jobService,
      super(ImportStatusState(snapshot: jobService.current)) {
    on<_ImportStatusSnapshotReceived>(_onSnapshot);
    on<ImportStatusCancelRequested>(_onCancel);
    on<ImportStatusDismissRequested>(_onDismiss);

    _sub = jobService.snapshots.listen((ImportJobSnapshot s) {
      if (!isClosed) add(_ImportStatusSnapshotReceived(s));
    });
  }

  final ImportJobService _jobService;
  StreamSubscription<ImportJobSnapshot>? _sub;

  void _onSnapshot(
    _ImportStatusSnapshotReceived event,
    Emitter<ImportStatusState> emit,
  ) {
    // Any arriving snapshot clears the dismissed flag so fresh activity is always visible.
    emit(ImportStatusState(snapshot: event.snapshot));
  }

  void _onCancel(
    ImportStatusCancelRequested event,
    Emitter<ImportStatusState> emit,
  ) {
    _jobService.cancel();
  }

  void _onDismiss(
    ImportStatusDismissRequested event,
    Emitter<ImportStatusState> emit,
  ) {
    emit(state.copyWith(dismissed: true));
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _sub = null;
    return super.close();
  }
}
