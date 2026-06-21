// lib/features/managed_copy/presentation/bloc/manual_backup_bloc.dart

import 'package:equatable/equatable.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/create_manual_backup.dart';
import '../../domain/entities/manual_backup_result.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class ManualBackupEvent extends Equatable {
  const ManualBackupEvent();
  @override
  List<Object?> get props => [];
}

/// Triggered by the user after confirming the backup dialog.
final class ManualBackupRequested extends ManualBackupEvent {
  const ManualBackupRequested();
}

// ── State ─────────────────────────────────────────────────────────────────────

class ManualBackupState extends Equatable {
  const ManualBackupState({
    this.busy = false,
    this.messageKey,
    this.sequence = 0,
  });

  final bool busy;

  /// l10n message key emitted with each outcome, null between operations.
  ///
  /// Values:
  /// - `'success'`        — backup created and verified.
  /// - `'not_configured'` — backup root not set in settings.
  /// - `'root_missing'`   — backup root directory not accessible.
  /// - `'failed'`         — backup service error.
  final String? messageKey;

  /// Incremented with every new message so [listenWhen] can fire on repeated
  /// outcomes without needing to compare messageKey strings.
  final int sequence;

  @override
  List<Object?> get props => [busy, messageKey, sequence];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class ManualBackupBloc extends Bloc<ManualBackupEvent, ManualBackupState> {
  ManualBackupBloc(this._createBackup) : super(const ManualBackupState()) {
    on<ManualBackupRequested>(_onRequested, transformer: droppable());
  }

  final CreateManualBackup _createBackup;

  Future<void> _onRequested(
    ManualBackupRequested event,
    Emitter<ManualBackupState> emit,
  ) async {
    if (state.busy) return;
    emit(const ManualBackupState(busy: true));

    await Future<void>.delayed(Duration.zero);
    final result = await _createBackup();

    final String messageKey = switch (result) {
      ManualBackupSuccess() => 'success',
      ManualBackupFailure(:final messageKey) => messageKey,
    };

    emit(
      ManualBackupState(
        busy: false,
        messageKey: messageKey,
        sequence: state.sequence + 1,
      ),
    );
  }
}
