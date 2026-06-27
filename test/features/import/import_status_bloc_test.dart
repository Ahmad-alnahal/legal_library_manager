// test/features/import/import_status_bloc_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/application/import_job_service.dart';
import 'package:legal_library_manager/features/import/application/import_job_snapshot.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/presentation/bloc/import_status_bloc.dart';

import 'support/import_fakes.dart';

const _valid = FolderValidationResult.valid(r'C:\src');
final _provider = FakeProtectedRootsProvider(
  const ProtectedRoots(databaseRoot: r'C:\db'),
);

ImportJobService _makeService({
  FakePdfScanner? scanner,
  FakeFileHasher? hasher,
  FakeImportRepository? repo,
}) {
  final r = repo ?? FakeImportRepository();
  return ImportJobService(
    coordinator: ImportCoordinator(
      validator: FakeFolderValidator(_valid),
      scanner: scanner ?? FakePdfScanner(const PdfScanResult(candidates: [])),
      hasher: hasher ?? FakeFileHasher(),
      inspector: FakePdfHealthInspector(),
      repository: r,
      clock: const SystemClock(),
      runner: syncRunner,
    ),
    protectedRootsProvider: _provider,
    repository: r,
    clock: const SystemClock(),
  );
}

void main() {
  test('initial state reflects service.current (idle)', () {
    final service = _makeService();
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    expect(bloc.state.snapshot.status, ImportJobStatus.idle);
    expect(bloc.state.isVisible, isFalse);
    expect(bloc.state.dismissed, isFalse);
  });

  test('snapshot received sets state and clears dismissed', () async {
    final gate = Completer<void>();
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(gate: gate),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    service.start(folder: r'C:\src', recursive: true);
    final running = await bloc.stream.firstWhere((s) => s.snapshot.isActive);

    expect(running.snapshot.status, ImportJobStatus.running);
    expect(running.isVisible, isTrue);
    expect(running.dismissed, isFalse);

    gate.complete();
    await service.snapshots.firstWhere((s) => s.isTerminal);
  });

  test('dismiss sets dismissed=true and hides visible banner', () async {
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    service.start(folder: r'C:\src', recursive: true);
    await bloc.stream.firstWhere((s) => s.snapshot.isTerminal);

    bloc.add(const ImportStatusDismissRequested());
    final dismissed = await bloc.stream.firstWhere((s) => s.dismissed);

    expect(dismissed.isVisible, isFalse);
  });

  test('new snapshot after dismiss clears dismissed flag', () async {
    final gate1 = Completer<void>();
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(gate: gate1),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    // First run → terminal → dismiss.
    service.start(folder: r'C:\src', recursive: true);
    gate1.complete();
    await bloc.stream.firstWhere((s) => s.snapshot.isTerminal);
    bloc.add(const ImportStatusDismissRequested());
    await bloc.stream.firstWhere((s) => s.dismissed);

    // Reset then start again.
    service.reset();
    await bloc.stream.firstWhere(
      (s) => s.snapshot.status == ImportJobStatus.idle,
    );

    // Idle snapshot clears dismissed.
    expect(bloc.state.dismissed, isFalse);

    // Start second run — running snapshot also keeps dismissed=false.
    final gate2 = Completer<void>();
    final service2 = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\b.pdf')]),
      ),
      hasher: FakeFileHasher(gate: gate2),
    );
    final bloc2 = ImportStatusBloc(jobService: service2);
    addTearDown(bloc2.close);
    addTearDown(service2.dispose);

    service2.start(folder: r'C:\src', recursive: true);
    final running = await bloc2.stream.firstWhere((s) => s.snapshot.isActive);
    expect(running.dismissed, isFalse);

    gate2.complete();
    await service2.snapshots.firstWhere((s) => s.isTerminal);
  });

  test('cancel forwards to service', () async {
    final gate = Completer<void>();
    final repo = FakeImportRepository();
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(
          candidates: [candidate(r'C:\src\a.pdf'), candidate(r'C:\src\b.pdf')],
        ),
      ),
      hasher: FakeFileHasher(gate: gate),
      repo: repo,
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    service.start(folder: r'C:\src', recursive: true);
    await bloc.stream.firstWhere((s) => s.snapshot.isActive);

    bloc.add(const ImportStatusCancelRequested());
    gate.complete();
    await bloc.stream.firstWhere((s) => s.snapshot.isTerminal);

    expect(repo.lastStatus, ImportBatchStatus.cancelled);
  });

  test('closing bloc cancels subscription but job continues', () async {
    final gate = Completer<void>();
    final repo = FakeImportRepository();
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(gate: gate),
      repo: repo,
    );
    final bloc = ImportStatusBloc(jobService: service);

    service.start(folder: r'C:\src', recursive: true);
    await bloc.stream.firstWhere((s) => s.snapshot.isActive);

    await bloc.close();
    expect(bloc.isClosed, isTrue);

    gate.complete();
    await service.snapshots.firstWhere((s) => s.isTerminal);
    expect(repo.lastStatus, ImportBatchStatus.completed);
    await service.dispose();
  });
}
