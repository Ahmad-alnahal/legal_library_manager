import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/use_cases/mark_document_ready_for_export.dart';
import '../../domain/entities/mark_ready_for_export_result.dart';

sealed class MarkReadyForExportEvent extends Equatable {
  const MarkReadyForExportEvent();
  @override
  List<Object?> get props => [];
}

final class MarkReadyForExportRequested extends MarkReadyForExportEvent {
  const MarkReadyForExportRequested(this.documentId);
  final int documentId;
  @override
  List<Object?> get props => [documentId];
}

enum MarkReadyForExportStatus { idle, running, success, ineligible, failed }

class MarkReadyForExportState extends Equatable {
  const MarkReadyForExportState({
    this.status = MarkReadyForExportStatus.idle,
    this.documentId,
    this.ineligibleReasons = const [],
    this.sequence = 0,
  });

  final MarkReadyForExportStatus status;
  final int? documentId;
  final List<String> ineligibleReasons;
  final int sequence;
  bool get isRunning => status == MarkReadyForExportStatus.running;

  @override
  List<Object?> get props => [status, documentId, ineligibleReasons, sequence];
}

class MarkReadyForExportBloc
    extends Bloc<MarkReadyForExportEvent, MarkReadyForExportState> {
  MarkReadyForExportBloc(MarkDocumentReadyForExport markReadyForExport)
    : this.executor(markReadyForExport.call);

  /// Testable presentation boundary that still accepts only a document ID.
  MarkReadyForExportBloc.executor(
    Future<MarkReadyForExportResult> Function(int) execute,
  ) : _execute = execute,
      super(const MarkReadyForExportState()) {
    on<MarkReadyForExportRequested>(_onRequested);
  }

  final Future<MarkReadyForExportResult> Function(int) _execute;
  bool _inFlight = false;

  Future<void> _onRequested(
    MarkReadyForExportRequested event,
    Emitter<MarkReadyForExportState> emit,
  ) async {
    if (_inFlight) return;
    _inFlight = true;
    emit(
      MarkReadyForExportState(
        status: MarkReadyForExportStatus.running,
        documentId: event.documentId,
        sequence: state.sequence,
      ),
    );
    try {
      final result = await _execute(event.documentId);
      emit(
        MarkReadyForExportState(
          status: switch (result) {
            MarkReadyForExportSuccess() => MarkReadyForExportStatus.success,
            MarkReadyForExportIneligible() =>
              MarkReadyForExportStatus.ineligible,
          },
          documentId: event.documentId,
          ineligibleReasons: switch (result) {
            MarkReadyForExportIneligible(:final reasons) => reasons,
            _ => const [],
          },
          sequence: state.sequence + 1,
        ),
      );
    } catch (_) {
      emit(
        MarkReadyForExportState(
          status: MarkReadyForExportStatus.failed,
          documentId: event.documentId,
          sequence: state.sequence + 1,
        ),
      );
    } finally {
      _inFlight = false;
    }
  }
}
