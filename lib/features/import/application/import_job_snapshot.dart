// lib/features/import/application/import_job_snapshot.dart

import 'package:equatable/equatable.dart';

import 'import_progress.dart';
import 'import_run_report.dart';

/// Observable lifecycle state of the singleton [ImportJobService].
enum ImportJobStatus {
  /// No import is running; the service is idle.
  idle,

  /// An import run (or retry) is in progress.
  running,

  /// Cooperative cancellation has been requested; the run is winding down.
  cancelling,

  /// The import completed successfully.
  completed,

  /// The import was cancelled by the user.
  cancelled,

  /// The import encountered an unrecoverable failure.
  failed,
}

/// Immutable snapshot of the [ImportJobService]'s current state.
///
/// Emitted on every state transition: status changes, progress ticks, and
/// terminal results. Consumers (BLoC, future global progress widget) subscribe
/// to [ImportJobService.snapshots] and receive these objects directly.
class ImportJobSnapshot extends Equatable {
  const ImportJobSnapshot({required this.status, this.progress, this.report});

  const ImportJobSnapshot.idle()
    : status = ImportJobStatus.idle,
      progress = null,
      report = null;

  final ImportJobStatus status;
  final ImportProgress? progress;
  final ImportRunReport? report;

  bool get isActive =>
      status == ImportJobStatus.running || status == ImportJobStatus.cancelling;

  bool get isTerminal =>
      status == ImportJobStatus.completed ||
      status == ImportJobStatus.cancelled ||
      status == ImportJobStatus.failed;

  ImportJobSnapshot copyWith({
    ImportJobStatus? status,
    ImportProgress? progress,
    ImportRunReport? report,
    bool clearProgress = false,
    bool clearReport = false,
  }) {
    return ImportJobSnapshot(
      status: status ?? this.status,
      progress: clearProgress ? null : (progress ?? this.progress),
      report: clearReport ? null : (report ?? this.report),
    );
  }

  @override
  List<Object?> get props => [status, progress, report];
}
