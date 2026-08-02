// lib/features/export/presentation/bloc/export_batch_bloc.dart

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/use_cases/generate_export_batch.dart';
import '../../application/use_cases/load_export_screen_data.dart';
import '../../domain/entities/export_batch_summary.dart';
import '../../domain/entities/export_screen_data.dart';
import '../../domain/entities/generate_export_batch_result.dart';

sealed class ExportBatchEvent extends Equatable {
  const ExportBatchEvent();
  @override
  List<Object?> get props => [];
}

final class ExportBatchScreenStarted extends ExportBatchEvent {
  const ExportBatchScreenStarted();
}

final class ExportBatchGenerateRequested extends ExportBatchEvent {
  const ExportBatchGenerateRequested();
}

final class ExportBatchHistoryRefreshRequested extends ExportBatchEvent {
  const ExportBatchHistoryRefreshRequested();
}

enum ExportBatchLoadStatus { initial, loading, ready, failure }

enum ExportBatchGenerateStatus {
  idle,
  running,
  success,
  failed,
  nothingToExport,
  allSkipped,
}

class ExportBatchState extends Equatable {
  const ExportBatchState({
    this.loadStatus = ExportBatchLoadStatus.initial,
    this.exportRoot,
    this.readyForExportCount = 0,
    this.batches = const [],
    this.generateStatus = ExportBatchGenerateStatus.idle,
    this.lastResult,
    this.isGenerating = false,
  });

  final ExportBatchLoadStatus loadStatus;
  final String? exportRoot;
  final int readyForExportCount;
  final List<ExportBatchSummary> batches;
  final ExportBatchGenerateStatus generateStatus;
  final GenerateExportBatchResult? lastResult;
  final bool isGenerating;

  ExportBatchState copyWith({
    ExportBatchLoadStatus? loadStatus,
    String? exportRoot,
    int? readyForExportCount,
    List<ExportBatchSummary>? batches,
    ExportBatchGenerateStatus? generateStatus,
    GenerateExportBatchResult? lastResult,
    bool clearLastResult = false,
    bool? isGenerating,
  }) {
    return ExportBatchState(
      loadStatus: loadStatus ?? this.loadStatus,
      exportRoot: exportRoot ?? this.exportRoot,
      readyForExportCount: readyForExportCount ?? this.readyForExportCount,
      batches: batches ?? this.batches,
      generateStatus: generateStatus ?? this.generateStatus,
      lastResult: clearLastResult ? null : lastResult ?? this.lastResult,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }

  @override
  List<Object?> get props => [
    loadStatus,
    exportRoot,
    readyForExportCount,
    batches,
    generateStatus,
    lastResult,
    isGenerating,
  ];
}

/// Coordinates the Export screen (P3.4.2): loads the export root, the
/// ready-for-export count, and batch history; drives on-demand generation via
/// [GenerateExportBatch].
class ExportBatchBloc extends Bloc<ExportBatchEvent, ExportBatchState> {
  ExportBatchBloc({
    required LoadExportScreenData loadExportScreenData,
    required GenerateExportBatch generateExportBatch,
  }) : this.executor(
         load: loadExportScreenData.call,
         generate: generateExportBatch.call,
       );

  /// Testable presentation boundary that accepts both the load and generate
  /// steps as plain functions.
  ExportBatchBloc.executor({required this._load, required this._generate})
    : super(const ExportBatchState()) {
    on<ExportBatchScreenStarted>(_onStarted);
    on<ExportBatchGenerateRequested>(_onGenerate);
    on<ExportBatchHistoryRefreshRequested>(_onHistoryRefresh);
  }

  final Future<ExportScreenData> Function() _load;
  final Future<GenerateExportBatchResult> Function() _generate;
  bool _inFlight = false;

  Future<void> _onStarted(
    ExportBatchScreenStarted event,
    Emitter<ExportBatchState> emit,
  ) async {
    emit(state.copyWith(loadStatus: ExportBatchLoadStatus.loading));
    try {
      final data = await _load();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          loadStatus: ExportBatchLoadStatus.ready,
          exportRoot: data.exportRoot,
          readyForExportCount: data.readyForExportCount,
          batches: data.batches,
        ),
      );
    } catch (_) {
      if (emit.isDone) return;
      emit(state.copyWith(loadStatus: ExportBatchLoadStatus.failure));
    }
  }

  Future<void> _onGenerate(
    ExportBatchGenerateRequested event,
    Emitter<ExportBatchState> emit,
  ) async {
    if (_inFlight) return;
    _inFlight = true;
    emit(
      state.copyWith(
        isGenerating: true,
        generateStatus: ExportBatchGenerateStatus.running,
        clearLastResult: true,
      ),
    );
    try {
      final result = await _generate();
      final status = switch (result) {
        GenerateExportBatchSuccess() => ExportBatchGenerateStatus.success,
        GenerateExportBatchNothingToExport() =>
          ExportBatchGenerateStatus.nothingToExport,
        GenerateExportBatchAllSkipped() => ExportBatchGenerateStatus.allSkipped,
        GenerateExportBatchFailed() => ExportBatchGenerateStatus.failed,
      };
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isGenerating: false,
            generateStatus: status,
            lastResult: result,
          ),
        );
      }
      await _reloadHistoryAndCount(emit);
    } catch (_) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isGenerating: false,
            generateStatus: ExportBatchGenerateStatus.failed,
            clearLastResult: true,
          ),
        );
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _onHistoryRefresh(
    ExportBatchHistoryRefreshRequested event,
    Emitter<ExportBatchState> emit,
  ) async {
    try {
      final data = await _load();
      if (emit.isDone) return;
      emit(state.copyWith(batches: data.batches));
    } catch (_) {
      // History refresh is best-effort; the existing list is kept on failure.
    }
  }

  Future<void> _reloadHistoryAndCount(Emitter<ExportBatchState> emit) async {
    try {
      final data = await _load();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          readyForExportCount: data.readyForExportCount,
          batches: data.batches,
        ),
      );
    } catch (_) {
      // Best-effort refresh; the generate result already emitted above.
    }
  }
}
