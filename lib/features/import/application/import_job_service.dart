// lib/features/import/application/import_job_service.dart

import 'dart:async';

import '../../../core/time/clock.dart';
import '../domain/entities/import_batch_report.dart';
import '../domain/entities/import_request.dart';
import '../domain/repositories/import_repository.dart';
import '../domain/services/file_hasher.dart';
import 'import_coordinator.dart';
import 'import_job_snapshot.dart';
import 'import_progress.dart';
import 'import_run_report.dart';
import 'protected_roots_provider.dart';

/// Singleton application-layer service that owns and survives the lifecycle of
/// one import run at a time.
///
/// Unlike the BLoC (which is recreated on every navigation), this service is
/// registered as a GetIt lazy singleton and keeps running when the user
/// navigates away from the import screen. The BLoC subscribes via [snapshots]
/// and unsubscribes on close — without cancelling the job.
///
/// Call [initialize] once at application startup (inside `initializeApplication`
/// in `marjiy_bootstrap.dart`) to mark any batch left in `running` state from a
/// previous crash as `interrupted`.
class ImportJobService {
  ImportJobService({
    required this.coordinator,
    required this.protectedRootsProvider,
    required this.repository,
    required this.clock,
  });

  final ImportCoordinator coordinator;
  final ProtectedRootsProvider protectedRootsProvider;
  final ImportRepository repository;
  final Clock clock;

  final StreamController<ImportJobSnapshot> _controller =
      StreamController<ImportJobSnapshot>.broadcast();

  ImportJobSnapshot _current = const ImportJobSnapshot.idle();
  MutableHashCancellation? _cancellation;

  /// The in-flight import future. Kept so [dispose] can drain it cleanly.
  Future<void>? _activeFuture;

  /// Broadcasts every state transition. New listeners immediately receive
  /// future emissions; use [current] to read the instantaneous snapshot.
  Stream<ImportJobSnapshot> get snapshots => _controller.stream;

  /// The most recent snapshot, always available synchronously.
  ImportJobSnapshot get current => _current;

  /// Marks any `running` batch as `interrupted`. Call once at app startup.
  Future<void> initialize() =>
      repository.markInterruptedBatches(now: clock.nowUtc());

  /// Starts a new import job for [folder]. No-op if a job is already active.
  void start({required String folder, required bool recursive}) {
    if (_current.isActive) return;
    final MutableHashCancellation cancellation = MutableHashCancellation();
    _cancellation = cancellation;
    _emit(
      _current.copyWith(
        status: ImportJobStatus.running,
        clearProgress: true,
        clearReport: true,
      ),
    );
    _activeFuture = _runImport(
      folder,
      recursive,
      cancellation,
    ).whenComplete(() => _activeFuture = null);
  }

  /// Retries retryable failures from [previous]. No-op if a job is active or
  /// [previous] has no retryable failures.
  void retry(ImportRunReport previous) {
    if (_current.isActive) return;
    if (!previous.hasRetryableFailures) return;
    final MutableHashCancellation cancellation = MutableHashCancellation();
    _cancellation = cancellation;
    _emit(_current.copyWith(status: ImportJobStatus.running));
    _activeFuture = _runRetry(
      previous,
      cancellation,
    ).whenComplete(() => _activeFuture = null);
  }

  /// Requests cooperative cancellation of the active job. No-op if idle.
  void cancel() {
    if (!_current.isActive) return;
    _cancellation?.cancel();
    _emit(_current.copyWith(status: ImportJobStatus.cancelling));
  }

  /// Resets the service to idle, discarding the last terminal report.
  /// No-op if a job is currently active.
  void reset() {
    if (_current.isActive) return;
    _emit(const ImportJobSnapshot.idle());
  }

  Future<void> _runImport(
    String folder,
    bool recursive,
    MutableHashCancellation cancellation,
  ) async {
    try {
      final ImportRequest request = ImportRequest(
        sourceFolder: folder,
        recursive: recursive,
        protectedRoots: await protectedRootsProvider.load(),
      );
      final ImportRunReport report = await coordinator.run(
        request,
        cancellation: cancellation,
        onProgress: _onProgress,
      );
      _cancellation = null;
      _emitTerminal(report);
    } catch (_) {
      _cancellation = null;
      _emit(
        _current.copyWith(status: ImportJobStatus.failed, clearProgress: true),
      );
    }
  }

  Future<void> _runRetry(
    ImportRunReport previous,
    MutableHashCancellation cancellation,
  ) async {
    try {
      final ImportRunReport report = await coordinator.retry(
        previous,
        cancellation: cancellation,
        onProgress: _onProgress,
      );
      _cancellation = null;
      _emitTerminal(report);
    } catch (_) {
      _cancellation = null;
      _emit(
        _current.copyWith(status: ImportJobStatus.failed, clearProgress: true),
      );
    }
  }

  void _onProgress(ImportProgress progress) {
    if (_controller.isClosed) return;
    // Preserve cancelling status while still emitting progress ticks.
    final ImportJobStatus nextStatus =
        _current.status == ImportJobStatus.cancelling
        ? ImportJobStatus.cancelling
        : ImportJobStatus.running;
    _emit(_current.copyWith(status: nextStatus, progress: progress));
  }

  void _emitTerminal(ImportRunReport report) {
    final ImportJobStatus status = switch (report.status) {
      ImportBatchStatus.completed => ImportJobStatus.completed,
      ImportBatchStatus.cancelled => ImportJobStatus.cancelled,
      ImportBatchStatus.failed => ImportJobStatus.failed,
      // A terminal report that is still "running" or "interrupted" should
      // never happen at this point; surface as failed rather than silently
      // showing success.
      ImportBatchStatus.running => ImportJobStatus.failed,
      ImportBatchStatus.interrupted => ImportJobStatus.failed,
    };
    _emit(ImportJobSnapshot(status: status, report: report));
  }

  void _emit(ImportJobSnapshot snapshot) {
    _current = snapshot;
    if (!_controller.isClosed) _controller.add(snapshot);
  }

  /// Cancels any active job and closes the broadcast stream. Called by GetIt
  /// on application shutdown (registered via the `dispose` callback).
  Future<void> dispose() async {
    _cancellation?.cancel();
    _cancellation = null;
    await _activeFuture?.then((_) {}, onError: (_) {});
    await _controller.close();
  }
}
