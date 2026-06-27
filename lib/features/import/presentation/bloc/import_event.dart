// lib/features/import/presentation/bloc/import_event.dart

part of 'import_bloc.dart';

/// Events for the import workflow.
sealed class ImportEvent extends Equatable {
  const ImportEvent();

  @override
  List<Object?> get props => const [];
}

/// The user selected a source folder (selection alone never scans/imports).
class ImportFolderSelected extends ImportEvent {
  const ImportFolderSelected(this.path);

  final String path;

  @override
  List<Object?> get props => [path];
}

/// The user toggled recursive scanning.
class ImportRecursiveToggled extends ImportEvent {
  const ImportRecursiveToggled(this.recursive);

  final bool recursive;

  @override
  List<Object?> get props => [recursive];
}

/// The user pressed start scan/import.
class ImportStartRequested extends ImportEvent {
  const ImportStartRequested();
}

/// The user requested cooperative cancellation of the active run.
class ImportCancelRequested extends ImportEvent {
  const ImportCancelRequested();
}

/// The user requested retrying retryable failures from the last report.
class ImportRetryRequested extends ImportEvent {
  const ImportRetryRequested();
}

/// The user reset the screen for a new import after a terminal state.
class ImportResetRequested extends ImportEvent {
  const ImportResetRequested();
}

/// Internal: the [ImportJobService] emitted a new snapshot.
///
/// Replaces the old per-phase Progressed / Finished / FailedInternally events.
/// The BLoC's stream subscription delivers these; they are never added by UI code.
class ImportJobSnapshotReceived extends ImportEvent {
  const ImportJobSnapshotReceived(this.snapshot);

  final ImportJobSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot];
}
