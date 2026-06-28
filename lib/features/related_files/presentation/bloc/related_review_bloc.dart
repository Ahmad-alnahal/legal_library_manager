// lib/features/related_files/presentation/bloc/related_review_bloc.dart
// ignore_for_file: prefer_initializing_formals

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/load_pending_candidates_use_case.dart';
import '../../application/update_candidate_status_use_case.dart';
import '../../domain/entities/candidate_status.dart';
import '../../domain/entities/related_file_review_row.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class RelatedReviewEvent extends Equatable {
  const RelatedReviewEvent();

  @override
  List<Object?> get props => const [];
}

class RelatedReviewLoadRequested extends RelatedReviewEvent {
  const RelatedReviewLoadRequested();
}

class RelatedReviewConfirmRequested extends RelatedReviewEvent {
  const RelatedReviewConfirmRequested({required this.candidateId});

  final int candidateId;

  @override
  List<Object?> get props => [candidateId];
}

class RelatedReviewRejectRequested extends RelatedReviewEvent {
  const RelatedReviewRejectRequested({required this.candidateId});

  final int candidateId;

  @override
  List<Object?> get props => [candidateId];
}

class RelatedReviewDismissRequested extends RelatedReviewEvent {
  const RelatedReviewDismissRequested({required this.candidateId});

  final int candidateId;

  @override
  List<Object?> get props => [candidateId];
}

// ── State ─────────────────────────────────────────────────────────────────────

enum RelatedReviewStatus { initial, loading, loaded, failure }

class RelatedReviewState extends Equatable {
  const RelatedReviewState({
    this.status = RelatedReviewStatus.initial,
    this.rows = const [],
    this.actionError = false,
  });

  final RelatedReviewStatus status;
  final List<RelatedFileReviewRow> rows;

  /// True after a confirm/reject/dismiss action fails. Reset on next
  /// successful action or reload.
  final bool actionError;

  RelatedReviewState copyWith({
    RelatedReviewStatus? status,
    List<RelatedFileReviewRow>? rows,
    bool? actionError,
  }) => RelatedReviewState(
    status: status ?? this.status,
    rows: rows ?? this.rows,
    actionError: actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [status, rows, actionError];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class RelatedReviewBloc extends Bloc<RelatedReviewEvent, RelatedReviewState> {
  RelatedReviewBloc({
    required LoadPendingCandidatesUseCase loadCandidates,
    required UpdateCandidateStatusUseCase updateStatus,
  }) : _loadCandidates = loadCandidates,
       _updateStatus = updateStatus,
       super(const RelatedReviewState()) {
    on<RelatedReviewLoadRequested>(_onLoad);
    on<RelatedReviewConfirmRequested>(_onConfirm);
    on<RelatedReviewRejectRequested>(_onReject);
    on<RelatedReviewDismissRequested>(_onDismiss);
    add(const RelatedReviewLoadRequested());
  }

  final LoadPendingCandidatesUseCase _loadCandidates;
  final UpdateCandidateStatusUseCase _updateStatus;

  Future<void> _onLoad(
    RelatedReviewLoadRequested event,
    Emitter<RelatedReviewState> emit,
  ) async {
    emit(
      state.copyWith(status: RelatedReviewStatus.loading, actionError: false),
    );
    try {
      final rows = await _loadCandidates();
      emit(state.copyWith(status: RelatedReviewStatus.loaded, rows: rows));
    } catch (_) {
      emit(state.copyWith(status: RelatedReviewStatus.failure));
    }
  }

  Future<void> _onConfirm(
    RelatedReviewConfirmRequested event,
    Emitter<RelatedReviewState> emit,
  ) => _handleAction(event.candidateId, CandidateStatus.confirmed, emit);

  Future<void> _onReject(
    RelatedReviewRejectRequested event,
    Emitter<RelatedReviewState> emit,
  ) => _handleAction(event.candidateId, CandidateStatus.rejected, emit);

  Future<void> _onDismiss(
    RelatedReviewDismissRequested event,
    Emitter<RelatedReviewState> emit,
  ) => _handleAction(event.candidateId, CandidateStatus.dismissed, emit);

  Future<void> _handleAction(
    int candidateId,
    CandidateStatus status,
    Emitter<RelatedReviewState> emit,
  ) async {
    try {
      await _updateStatus(candidateId, status);
      // Optimistically remove the acted-on row without a full reload.
      final updated = state.rows
          .where((r) => r.candidateId != candidateId)
          .toList();
      emit(state.copyWith(rows: updated, actionError: false));
    } catch (_) {
      emit(state.copyWith(actionError: true));
    }
  }
}
