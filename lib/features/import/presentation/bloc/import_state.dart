// lib/features/import/presentation/bloc/import_state.dart

part of 'import_bloc.dart';

/// High-level status of the import screen.
enum ImportStatus {
  idle,
  validating,
  scanning,
  importing,
  cancelling,
  completed,
  cancelled,
  failed,
}

/// Immutable state for the import workflow.
class ImportState extends Equatable {
  const ImportState({
    this.status = ImportStatus.idle,
    this.selectedFolder,
    this.recursive = true,
    this.progress,
    this.report,
  });

  final ImportStatus status;
  final String? selectedFolder;
  final bool recursive;
  final ImportProgress? progress;
  final ImportRunReport? report;

  /// True while a run/retry is in flight (used to reject a second start).
  bool get isActive =>
      status == ImportStatus.validating ||
      status == ImportStatus.scanning ||
      status == ImportStatus.importing ||
      status == ImportStatus.cancelling;

  bool get isTerminal =>
      status == ImportStatus.completed ||
      status == ImportStatus.cancelled ||
      status == ImportStatus.failed;

  bool get canStart =>
      !isActive && selectedFolder != null && selectedFolder!.trim().isNotEmpty;

  ImportState copyWith({
    ImportStatus? status,
    String? selectedFolder,
    bool? recursive,
    ImportProgress? progress,
    ImportRunReport? report,
    bool clearProgress = false,
    bool clearReport = false,
  }) {
    return ImportState(
      status: status ?? this.status,
      selectedFolder: selectedFolder ?? this.selectedFolder,
      recursive: recursive ?? this.recursive,
      progress: clearProgress ? null : (progress ?? this.progress),
      report: clearReport ? null : (report ?? this.report),
    );
  }

  @override
  List<Object?> get props => [
    status,
    selectedFolder,
    recursive,
    progress,
    report,
  ];
}
