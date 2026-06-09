// test/features/import/import_bloc_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/domain/repositories/import_repository.dart';
import 'package:legal_library_manager/features/import/presentation/bloc/import_bloc.dart';

import 'support/import_fakes.dart';

void main() {
  late AppDatabase db;
  late DriftImportRepository repo;

  const valid = FolderValidationResult.valid(r'C:\src');
  final provider = FakeProtectedRootsProvider(
    const ProtectedRoots(databaseRoot: r'C:\db'),
  );

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftImportRepository(db);
  });

  tearDown(() => db.close());

  ImportBloc buildBloc({
    required FakePdfScanner scanner,
    required FakeFileHasher hasher,
    ImportRepository? repository,
  }) {
    final coordinator = ImportCoordinator(
      validator: FakeFolderValidator(valid),
      scanner: scanner,
      hasher: hasher,
      inspector: FakePdfHealthInspector(),
      repository: repository ?? repo,
      clock: const SystemClock(),
      runner: syncRunner,
    );
    return ImportBloc(
      coordinator: coordinator,
      protectedRootsProvider: provider,
    );
  }

  test('start runs to completed with a report', () async {
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(),
    );
    addTearDown(bloc.close);

    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());

    final terminal = await bloc.stream.firstWhere((s) => s.isTerminal);
    expect(terminal.status, ImportStatus.completed);
    expect(terminal.report, isNotNull);
    expect(terminal.report!.importedNewCount, 1);
  });

  test('a second start while active is rejected', () async {
    final gate = Completer<void>();
    final scanner = FakePdfScanner(
      PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
    );
    final bloc = buildBloc(
      scanner: scanner,
      hasher: FakeFileHasher(gate: gate),
    );
    addTearDown(bloc.close);

    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isActive);
    // Second start while the first run is gated/active.
    bloc.add(const ImportStartRequested());
    await pumpEventQueue();

    expect(scanner.calls, 1); // only one run started

    gate.complete();
    final terminal = await bloc.stream.firstWhere((s) => s.isTerminal);
    expect(terminal.status, ImportStatus.completed);
  });

  test('cancel during a run yields a cancelled terminal state', () async {
    final gate = Completer<void>();
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(
          candidates: [candidate(r'C:\src\a.pdf'), candidate(r'C:\src\b.pdf')],
        ),
      ),
      hasher: FakeFileHasher(gate: gate),
    );
    addTearDown(bloc.close);

    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isActive);

    bloc.add(const ImportCancelRequested());
    await bloc.stream.firstWhere((s) => s.status == ImportStatus.cancelling);
    gate.complete();

    final terminal = await bloc.stream.firstWhere((s) => s.isTerminal);
    expect(terminal.status, ImportStatus.cancelled);
  });

  test('reset returns to idle and keeps the selected folder', () async {
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(),
    );
    addTearDown(bloc.close);

    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isTerminal);

    bloc.add(const ImportResetRequested());
    final idle = await bloc.stream.firstWhere(
      (s) => s.status == ImportStatus.idle,
    );
    expect(idle.report, isNull);
    expect(idle.selectedFolder, r'C:\src');
  });

  test('recursive toggle updates state while idle', () async {
    final bloc = buildBloc(
      scanner: FakePdfScanner(const PdfScanResult(candidates: [])),
      hasher: FakeFileHasher(),
    );
    addTearDown(bloc.close);

    expect(bloc.state.recursive, isTrue);
    bloc.add(const ImportRecursiveToggled(false));
    final updated = await bloc.stream.firstWhere((s) => !s.recursive);
    expect(updated.recursive, isFalse);
  });

  // --- BLoC active-future lifecycle ---

  test('closing while idle completes immediately without error', () async {
    final bloc = buildBloc(
      scanner: FakePdfScanner(const PdfScanResult(candidates: [])),
      hasher: FakeFileHasher(),
    );
    await bloc.close();
    expect(bloc.isClosed, isTrue);
  });

  test(
    'closing during an active run cancels and settles the active future',
    () async {
      final gate = Completer<void>();
      final fakeRepo = FakeImportRepository();
      final bloc = buildBloc(
        scanner: FakePdfScanner(
          PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
        ),
        hasher: FakeFileHasher(gate: gate),
        repository: fakeRepo,
      );

      bloc.add(const ImportFolderSelected(r'C:\src'));
      bloc.add(const ImportStartRequested());
      await bloc.stream.firstWhere((s) => s.isActive);

      // Close (cancels token) then unblock the hasher. close() waits for the
      // active future to settle before resolving.
      final closeFuture = bloc.close();
      gate.complete();
      await closeFuture;

      expect(bloc.isClosed, isTrue);
      // The run was cancelled (not completed or left stuck in running).
      expect(fakeRepo.lastStatus, ImportBatchStatus.cancelled);
    },
  );

  test('after close, no additional repository calls occur', () async {
    final fakeRepo = FakeImportRepository();
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(),
      repository: fakeRepo,
    );

    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isTerminal);

    // Import is done; record the last known repository state.
    expect(fakeRepo.lastStatus, ImportBatchStatus.completed);
    await bloc.close();

    // Status must not have changed: close() must not trigger any further
    // repository operations on an already-settled import.
    expect(fakeRepo.lastStatus, ImportBatchStatus.completed);
    expect(bloc.isClosed, isTrue);
  });
}
