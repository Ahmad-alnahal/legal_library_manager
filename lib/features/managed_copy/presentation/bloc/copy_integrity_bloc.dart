// lib/features/managed_copy/presentation/bloc/copy_integrity_bloc.dart

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../security/application/unauthorized_exception.dart';
import '../../domain/entities/reconcile_integrity_result.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class CopyIntegrityEvent extends Equatable {
  const CopyIntegrityEvent();
  @override
  List<Object?> get props => [];
}

/// User-triggered bulk integrity check across all registered managed copies.
final class CopyIntegrityCheckRequested extends CopyIntegrityEvent {
  const CopyIntegrityCheckRequested();
}

// ── State ─────────────────────────────────────────────────────────────────────

class CopyIntegrityState extends Equatable {
  const CopyIntegrityState({
    this.busy = false,
    this.messageKey,
    this.issueCount = 0,
    this.sequence = 0,
  });

  final bool busy;

  /// l10n message key set after each completed check, null between checks.
  ///
  /// Values:
  /// - `'clean'`  — all managed copies are healthy.
  /// - `'issues'` — one or more files are missing, corrupted, or failed.
  /// - `'failed'` — the use case threw an unexpected exception.
  final String? messageKey;

  /// Total number of problematic files (missing + corrupted + failed).
  /// Meaningful only when [messageKey] is `'issues'`.
  final int issueCount;

  /// Incremented with every new [messageKey] so listeners detect repeated
  /// outcomes without comparing messageKey strings.
  final int sequence;

  @override
  List<Object?> get props => [busy, messageKey, issueCount, sequence];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class CopyIntegrityBloc extends Bloc<CopyIntegrityEvent, CopyIntegrityState> {
  CopyIntegrityBloc(Future<ReconcileIntegrityResult> Function() reconcile)
    : _reconcile = reconcile,
      super(const CopyIntegrityState()) {
    on<CopyIntegrityCheckRequested>(
      _onCheckRequested,
      transformer: droppable(),
    );
  }

  final Future<ReconcileIntegrityResult> Function() _reconcile;

  Future<void> _onCheckRequested(
    CopyIntegrityCheckRequested event,
    Emitter<CopyIntegrityState> emit,
  ) async {
    emit(const CopyIntegrityState(busy: true));
    try {
      final result = await _reconcile();
      final issueCount =
          result.missingCount + result.corruptedCount + result.failedCount;
      emit(
        CopyIntegrityState(
          busy: false,
          messageKey: result.isClean ? 'clean' : 'issues',
          issueCount: issueCount,
          sequence: state.sequence + 1,
        ),
      );
    } on UnauthorizedException {
      emit(
        CopyIntegrityState(
          busy: false,
          messageKey: 'unauthorized',
          sequence: state.sequence + 1,
        ),
      );
    } catch (_) {
      emit(
        CopyIntegrityState(
          busy: false,
          messageKey: 'failed',
          sequence: state.sequence + 1,
        ),
      );
    }
  }
}
