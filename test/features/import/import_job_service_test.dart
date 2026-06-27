// test/features/import/import_job_service_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/application/import_job_service.dart';
import 'package:legal_library_manager/features/import/application/import_job_snapshot.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';

import 'support/import_fakes.dart';

/// Builds an [ImportJobService] wired to in-memory fakes.
ImportJobService buildService({
  FakePdfScanner? scanner,
  FakeFileHasher? hasher,
  FakeImportRepository? repository,
  Completer<void>? gate,
}) {
  final FakeImportRepository repo = repository ?? FakeImportRepository();
  final coordinator = ImportCoordinator(
    validator: FakeFolderValidator(
      const FolderValidationResult.valid(r'C:\src'),
    ),
    scanner:
        scanner ??
        FakePdfScanner(PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')])),
    hasher: hasher ?? FakeFileHasher(gate: gate),
    inspector: FakePdfHealthInspector(),
    repository: repo,
    clock: const SystemClock(),
    runner: syncRunner,
  );
  return ImportJobService(
    coordinator: coordinator,
    protectedRootsProvider: FakeProtectedRootsProvider(
      const ProtectedRoots(databaseRoot: r'C:\db'),
    ),
    repository: repo,
    clock: const SystemClock(),
  );
}

void main() {
  group('ImportJobService — lifecycle', () {
    test('starts idle', () {
      final service = buildService();
      expect(service.current.status, ImportJobStatus.idle);
    });

    test('start transitions to running then completed', () async {
      final service = buildService();
      addTearDown(service.dispose);

      final List<ImportJobStatus> statuses = [];
      final sub = service.snapshots.listen((s) => statuses.add(s.status));
      addTearDown(sub.cancel);

      service.start(folder: r'C:\src', recursive: true);
      await service.snapshots.firstWhere((s) => s.isTerminal);

      expect(statuses, contains(ImportJobStatus.running));
      expect(statuses.last, ImportJobStatus.completed);
      expect(service.current.report, isNotNull);
      expect(service.current.report!.importedNewCount, 1);
    });

    test('second start while active is rejected', () async {
      final gate = Completer<void>();
      final service = buildService(gate: gate);
      addTearDown(service.dispose);

      service.start(folder: r'C:\src', recursive: true);
      await service.snapshots.firstWhere((s) => s.isActive);

      // Attempt a second start — should be a no-op.
      service.start(folder: r'C:\src', recursive: false);
      await pumpEventQueue();

      gate.complete();
      await service.snapshots.firstWhere((s) => s.isTerminal);

      // Only one import ran.
      expect(service.current.status, ImportJobStatus.completed);
    });

    test('cancel transitions to cancelling then cancelled', () async {
      final gate = Completer<void>();
      final service = buildService(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [
              candidate(r'C:\src\a.pdf'),
              candidate(r'C:\src\b.pdf'),
            ],
          ),
        ),
        gate: gate,
      );
      addTearDown(service.dispose);

      service.start(folder: r'C:\src', recursive: true);
      await service.snapshots.firstWhere((s) => s.isActive);

      service.cancel();
      expect(service.current.status, ImportJobStatus.cancelling);

      gate.complete();
      await service.snapshots.firstWhere((s) => s.isTerminal);
      expect(service.current.status, ImportJobStatus.cancelled);
    });

    test('reset after terminal clears report and returns to idle', () async {
      final service = buildService();
      addTearDown(service.dispose);

      service.start(folder: r'C:\src', recursive: true);
      await service.snapshots.firstWhere((s) => s.isTerminal);

      service.reset();
      expect(service.current.status, ImportJobStatus.idle);
      expect(service.current.report, isNull);
    });

    test('reset while active is a no-op', () async {
      final gate = Completer<void>();
      final service = buildService(gate: gate);
      addTearDown(service.dispose);

      service.start(folder: r'C:\src', recursive: true);
      await service.snapshots.firstWhere((s) => s.isActive);

      service.reset(); // ignored while running
      expect(service.current.isActive, isTrue);

      gate.complete();
      await service.snapshots.firstWhere((s) => s.isTerminal);
    });

    test('dispose cancels active job and closes stream', () async {
      final gate = Completer<void>();
      final service = buildService(gate: gate);

      service.start(folder: r'C:\src', recursive: true);
      await service.snapshots.firstWhere((s) => s.isActive);

      final disposeFuture = service.dispose();
      gate.complete();
      await disposeFuture;

      expect(service.current.status, isNot(ImportJobStatus.running));
    });
  });

  group('ImportJobService — initialize', () {
    test('markInterruptedBatches is called on initialize', () async {
      final repo = FakeImportRepository();
      final service = ImportJobService(
        coordinator: ImportCoordinator(
          validator: FakeFolderValidator(
            const FolderValidationResult.valid(r'C:\src'),
          ),
          scanner: FakePdfScanner(const PdfScanResult(candidates: [])),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(),
          repository: repo,
          clock: const SystemClock(),
          runner: syncRunner,
        ),
        protectedRootsProvider: FakeProtectedRootsProvider(
          const ProtectedRoots(databaseRoot: r'C:\db'),
        ),
        repository: repo,
        clock: const SystemClock(),
      );
      addTearDown(service.dispose);

      expect(repo.markInterruptedCalls, 0);
      await service.initialize();
      expect(repo.markInterruptedCalls, 1);
    });
  });

  group('ImportJobService — job survives BLoC disposal analogue', () {
    test(
      'snapshot stream emits to new listener after first listener unsubscribes',
      () async {
        final gate = Completer<void>();
        final service = buildService(gate: gate);
        addTearDown(service.dispose);

        service.start(folder: r'C:\src', recursive: true);

        // First listener (simulates initial BLoC).
        final sub1 = service.snapshots.listen((_) {});
        await service.snapshots.firstWhere((s) => s.isActive);
        await sub1.cancel(); // BLoC disposed

        // Second listener (simulates new BLoC after navigation).
        final List<ImportJobStatus> received = [];
        final sub2 = service.snapshots.listen((s) => received.add(s.status));
        addTearDown(sub2.cancel);

        gate.complete();
        await service.snapshots.firstWhere((s) => s.isTerminal);

        expect(received, contains(ImportJobStatus.completed));
      },
    );
  });

  group('ImportJobService — pairedCount in batch (regression)', () {
    test('completed batch records paired word source count', () async {
      final repo = FakeImportRepository();
      final service = ImportJobService(
        coordinator: ImportCoordinator(
          validator: FakeFolderValidator(
            const FolderValidationResult.valid(r'C:\src'),
          ),
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\doc.pdf'),
                candidate(r'C:\src\doc.doc', extension: '.doc'),
              ],
            ),
          ),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(),
          repository: repo,
          clock: const SystemClock(),
          runner: syncRunner,
        ),
        protectedRootsProvider: FakeProtectedRootsProvider(
          const ProtectedRoots(databaseRoot: r'C:\db'),
        ),
        repository: repo,
        clock: const SystemClock(),
      );
      addTearDown(service.dispose);

      service.start(folder: r'C:\src', recursive: true);
      final terminal = await service.snapshots.firstWhere((s) => s.isTerminal);

      expect(terminal.status, ImportJobStatus.completed);
      expect(terminal.report!.pairedWordSourceCount, 1);
    });
  });
}
