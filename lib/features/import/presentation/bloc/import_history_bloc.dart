// lib/features/import/presentation/bloc/import_history_bloc.dart

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/import_job_snapshot.dart';
import '../../domain/entities/import_batch_record.dart';
import '../../domain/usecases/get_recent_import_batches_use_case.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class ImportHistoryEvent extends Equatable {
  const ImportHistoryEvent();

  @override
  List<Object?> get props => const [];
}

/// Triggers a (re)load of recent import batches from the repository.
///
/// Fired automatically on BLoC creation and whenever a terminal
/// [ImportJobSnapshot] arrives from the job stream.
class ImportHistoryLoadRequested extends ImportHistoryEvent {
  const ImportHistoryLoadRequested();
}

// ── State ─────────────────────────────────────────────────────────────────────

enum ImportHistoryStatus { initial, loading, loaded, failure }

class ImportHistoryState extends Equatable {
  const ImportHistoryState({
    this.status = ImportHistoryStatus.initial,
    this.batches = const [],
  });

  final ImportHistoryStatus status;
  final List<ImportBatchRecord> batches;

  ImportHistoryState copyWith({
    ImportHistoryStatus? status,
    List<ImportBatchRecord>? batches,
  }) {
    return ImportHistoryState(
      status: status ?? this.status,
      batches: batches ?? this.batches,
    );
  }

  @override
  List<Object?> get props => [status, batches];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

/// Loads recent import batch records and auto-refreshes when a job completes.
///
/// Subscribes to [jobSnapshots] to detect terminal runs (completed, failed,
/// cancelled) and reload the history automatically. Closing the BLoC cancels
/// the subscription. Does not retry or resume old batches — those actions
/// require per-file checkpoint data that is not persisted (deferred).
class ImportHistoryBloc extends Bloc<ImportHistoryEvent, ImportHistoryState> {
  ImportHistoryBloc({
    required this._getRecentBatches,
    required Stream<ImportJobSnapshot> jobSnapshots,
  }) : super(const ImportHistoryState()) {
    on<ImportHistoryLoadRequested>(_onLoad);

    _sub = jobSnapshots.listen(_onJobSnapshot);

    // Trigger the initial load immediately.
    add(const ImportHistoryLoadRequested());
  }

  final GetRecentImportBatchesUseCase _getRecentBatches;
  StreamSubscription<ImportJobSnapshot>? _sub;

  void _onJobSnapshot(ImportJobSnapshot snap) {
    // Auto-refresh only on terminal (completed/failed/cancelled) snapshots.
    if (snap.isTerminal && !isClosed) {
      add(const ImportHistoryLoadRequested());
    }
  }

  Future<void> _onLoad(
    ImportHistoryLoadRequested event,
    Emitter<ImportHistoryState> emit,
  ) async {
    emit(state.copyWith(status: ImportHistoryStatus.loading));
    try {
      final batches = await _getRecentBatches();
      emit(
        state.copyWith(status: ImportHistoryStatus.loaded, batches: batches),
      );
    } catch (_) {
      emit(state.copyWith(status: ImportHistoryStatus.failure));
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _sub = null;
    return super.close();
  }
}
