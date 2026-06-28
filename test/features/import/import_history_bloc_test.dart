// test/features/import/import_history_bloc_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/application/import_job_snapshot.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_record.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/usecases/get_recent_import_batches_use_case.dart';
import 'package:legal_library_manager/features/import/presentation/bloc/import_history_bloc.dart';

import 'support/import_fakes.dart';

ImportBatchRecord _fakeBatch() => ImportBatchRecord(
  id: 1,
  batchCode: 'IMPORT-0000001',
  sourceFolder: r'C:\src',
  status: ImportBatchStatus.completed,
  discoveredCount: 5,
  importedCount: 4,
  duplicateCount: 0,
  failedCount: 1,
  pairedCount: 0,
  startedAt: DateTime.utc(2026, 6, 28, 10),
  completedAt: DateTime.utc(2026, 6, 28, 11),
);

ImportHistoryBloc _buildBloc({
  FakeImportRepository? repo,
  Stream<ImportJobSnapshot>? jobSnapshots,
}) {
  final r = repo ?? FakeImportRepository();
  return ImportHistoryBloc(
    getRecentBatches: GetRecentImportBatchesUseCase(r),
    jobSnapshots: jobSnapshots ?? const Stream.empty(),
  );
}

void main() {
  test('initial state has status initial and empty batches', () {
    final bloc = _buildBloc();
    addTearDown(bloc.close);

    expect(bloc.state.status, ImportHistoryStatus.initial);
    expect(bloc.state.batches, isEmpty);
  });

  test('emits loading then loaded with empty list when repo is empty', () async {
    final bloc = _buildBloc();
    addTearDown(bloc.close);

    await expectLater(
      bloc.stream,
      emitsInOrder([
        predicate<ImportHistoryState>(
          (s) => s.status == ImportHistoryStatus.loading,
          'loading',
        ),
        predicate<ImportHistoryState>(
          (s) => s.status == ImportHistoryStatus.loaded && s.batches.isEmpty,
          'loaded with empty list',
        ),
      ]),
    );
  });

  test('emits loaded with batches when repo returns records', () async {
    final repo = FakeImportRepository(recentBatches: [_fakeBatch()]);
    final bloc = _buildBloc(repo: repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.loaded);

    expect(bloc.state.batches, hasLength(1));
    expect(bloc.state.batches.first.batchCode, 'IMPORT-0000001');
  });

  test('emits failure when use case throws', () async {
    final repo = FakeImportRepository(failGetRecentBatches: true);
    final bloc = _buildBloc(repo: repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.failure);

    expect(bloc.state.batches, isEmpty);
  });

  test('auto-reloads on completed terminal snapshot', () async {
    final controller = StreamController<ImportJobSnapshot>.broadcast();
    addTearDown(controller.close);
    final bloc = _buildBloc(jobSnapshots: controller.stream);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.loaded);

    int loadingCount = 0;
    final sub = bloc.stream.listen((s) {
      if (s.status == ImportHistoryStatus.loading) loadingCount++;
    });

    controller.add(const ImportJobSnapshot(status: ImportJobStatus.completed));
    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.loaded);

    expect(loadingCount, 1);
    await sub.cancel();
  });

  test('auto-reloads on failed terminal snapshot', () async {
    final controller = StreamController<ImportJobSnapshot>.broadcast();
    addTearDown(controller.close);
    final bloc = _buildBloc(jobSnapshots: controller.stream);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.loaded);

    int loadingCount = 0;
    final sub = bloc.stream.listen((s) {
      if (s.status == ImportHistoryStatus.loading) loadingCount++;
    });

    controller.add(const ImportJobSnapshot(status: ImportJobStatus.failed));
    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.loaded);

    expect(loadingCount, 1);
    await sub.cancel();
  });

  test('does not reload on idle snapshot', () async {
    final controller = StreamController<ImportJobSnapshot>.broadcast();
    addTearDown(controller.close);
    final bloc = _buildBloc(jobSnapshots: controller.stream);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.loaded);

    int loadingCount = 0;
    final sub = bloc.stream.listen((s) {
      if (s.status == ImportHistoryStatus.loading) loadingCount++;
    });

    controller.add(const ImportJobSnapshot.idle());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(loadingCount, 0);
    await sub.cancel();
  });

  test('does not reload on running snapshot', () async {
    final controller = StreamController<ImportJobSnapshot>.broadcast();
    addTearDown(controller.close);
    final bloc = _buildBloc(jobSnapshots: controller.stream);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == ImportHistoryStatus.loaded);

    int loadingCount = 0;
    final sub = bloc.stream.listen((s) {
      if (s.status == ImportHistoryStatus.loading) loadingCount++;
    });

    controller.add(const ImportJobSnapshot(status: ImportJobStatus.running));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(loadingCount, 0);
    await sub.cancel();
  });
}
