// lib/features/managed_copy/presentation/bloc/recovery_review_bloc.dart

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/cleanup_recovery_artifacts.dart';
import '../../application/load_recovery_review.dart';
import '../../domain/entities/cleanup_recovery_result.dart';
import '../../domain/entities/recovery_artifact_summary.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class RecoveryReviewEvent extends Equatable {
  const RecoveryReviewEvent();
  @override
  List<Object?> get props => [];
}

/// Triggers loading of the typed recovery artifact summary.
final class RecoveryReviewStarted extends RecoveryReviewEvent {
  const RecoveryReviewStarted();
}

/// Triggered after the user has confirmed the cleanup dialog.
final class RecoveryReviewCleanupConfirmed extends RecoveryReviewEvent {
  const RecoveryReviewCleanupConfirmed();
}

// ── State ─────────────────────────────────────────────────────────────────────

class RecoveryReviewState extends Equatable {
  const RecoveryReviewState({
    this.loading = false,
    this.cleaningUp = false,
    this.summary,
    this.cleanupMessageKey,
    this.sequence = 0,
  });

  final bool loading;
  final bool cleaningUp;

  /// Typed summary loaded by [LoadRecoveryReview]. Null while loading or when
  /// inspection failed. The UI reads only count properties — never raw paths.
  final RecoveryArtifactSummary? summary;

  /// l10n message key set after a cleanup attempt:
  /// `'cleaned'` | `'partial_failure'` | `'failed'` | `'nothing_to_clean'`
  final String? cleanupMessageKey;

  /// Incremented with every new [cleanupMessageKey] so listeners can distinguish
  /// repeated outcomes.
  final int sequence;

  RecoveryReviewState copyWith({
    bool? loading,
    bool? cleaningUp,
    RecoveryArtifactSummary? summary,
  }) {
    return RecoveryReviewState(
      loading: loading ?? this.loading,
      cleaningUp: cleaningUp ?? this.cleaningUp,
      summary: summary ?? this.summary,
      cleanupMessageKey: cleanupMessageKey,
      sequence: sequence,
    );
  }

  @override
  List<Object?> get props => [
    loading,
    cleaningUp,
    summary,
    cleanupMessageKey,
    sequence,
  ];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class RecoveryReviewBloc
    extends Bloc<RecoveryReviewEvent, RecoveryReviewState> {
  RecoveryReviewBloc(this._loadReview, this._cleanup)
    : super(const RecoveryReviewState()) {
    on<RecoveryReviewStarted>(_onStarted);
    on<RecoveryReviewCleanupConfirmed>(_onCleanup, transformer: droppable());
  }

  final LoadRecoveryReview _loadReview;
  final CleanupRecoveryArtifacts _cleanup;

  Future<void> _onStarted(
    RecoveryReviewStarted event,
    Emitter<RecoveryReviewState> emit,
  ) async {
    emit(const RecoveryReviewState(loading: true));
    final summary = await _loadReview();
    emit(RecoveryReviewState(loading: false, summary: summary));
  }

  Future<void> _onCleanup(
    RecoveryReviewCleanupConfirmed event,
    Emitter<RecoveryReviewState> emit,
  ) async {
    final summary = state.summary;
    if (summary == null) return;

    emit(state.copyWith(cleaningUp: true));

    final result = await _cleanup(summary);

    final String messageKey = switch (result) {
      CleanupRecoveryResult.cleaned => 'cleaned',
      CleanupRecoveryResult.partialFailure => 'partial_failure',
      CleanupRecoveryResult.failed => 'failed',
      CleanupRecoveryResult.nothingToClean => 'nothing_to_clean',
    };

    emit(
      RecoveryReviewState(
        loading: false,
        cleaningUp: false,
        summary: null,
        cleanupMessageKey: messageKey,
        sequence: state.sequence + 1,
      ),
    );
  }
}
