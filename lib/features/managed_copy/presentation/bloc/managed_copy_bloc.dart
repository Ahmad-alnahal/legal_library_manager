import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/managed_copy_use_case.dart';
import '../../domain/entities/managed_copy_error.dart';
import '../../domain/entities/managed_copy_result.dart';

sealed class ManagedCopyEvent extends Equatable {
  const ManagedCopyEvent();
  @override
  List<Object?> get props => [];
}

final class ManagedCopyRequested extends ManagedCopyEvent {
  const ManagedCopyRequested(this.documentId);
  final int documentId;
  @override
  List<Object?> get props => [documentId];
}

enum ManagedCopyStatus { idle, running, success, blocked, failed, recovery }

class ManagedCopyState extends Equatable {
  const ManagedCopyState({
    this.status = ManagedCopyStatus.idle,
    this.documentId,
    this.error,
    this.sequence = 0,
  });

  final ManagedCopyStatus status;
  final int? documentId;
  final ManagedCopyError? error;
  final int sequence;
  bool get isRunning => status == ManagedCopyStatus.running;

  @override
  List<Object?> get props => [status, documentId, error, sequence];
}

class ManagedCopyBloc extends Bloc<ManagedCopyEvent, ManagedCopyState> {
  ManagedCopyBloc(ManagedCopyUseCase copy) : this.executor(copy.execute);

  /// Testable presentation boundary that still accepts only a document ID.
  ManagedCopyBloc.executor(Future<ManagedCopyResult> Function(int) execute)
    : _execute = execute,
      super(const ManagedCopyState()) {
    on<ManagedCopyRequested>(_onRequested);
  }

  final Future<ManagedCopyResult> Function(int) _execute;
  bool _inFlight = false;

  Future<void> _onRequested(
    ManagedCopyRequested event,
    Emitter<ManagedCopyState> emit,
  ) async {
    if (_inFlight) return;
    _inFlight = true;
    emit(
      ManagedCopyState(
        status: ManagedCopyStatus.running,
        documentId: event.documentId,
        sequence: state.sequence,
      ),
    );
    try {
      final result = await _execute(event.documentId);
      emit(
        ManagedCopyState(
          status: switch (result) {
            ManagedCopySuccess() => ManagedCopyStatus.success,
            ManagedCopyBlocked() => ManagedCopyStatus.blocked,
            ManagedCopyFailed() => ManagedCopyStatus.failed,
            ManagedCopyRecoveryRequired() => ManagedCopyStatus.recovery,
          },
          documentId: event.documentId,
          error: switch (result) {
            ManagedCopyBlocked(:final error) => error,
            ManagedCopyFailed(:final error) => error,
            _ => null,
          },
          sequence: state.sequence + 1,
        ),
      );
    } catch (_) {
      emit(
        ManagedCopyState(
          status: ManagedCopyStatus.failed,
          documentId: event.documentId,
          error: ManagedCopyError.unexpectedFailure,
          sequence: state.sequence + 1,
        ),
      );
    } finally {
      _inFlight = false;
    }
  }
}
