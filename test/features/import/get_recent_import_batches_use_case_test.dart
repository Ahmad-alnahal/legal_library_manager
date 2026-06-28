// test/features/import/get_recent_import_batches_use_case_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_record.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/usecases/get_recent_import_batches_use_case.dart';

import 'support/import_fakes.dart';

void main() {
  ImportBatchRecord fakeBatch(int id) => ImportBatchRecord(
    id: id,
    batchCode: 'IMPORT-${id.toString().padLeft(7, '0')}',
    sourceFolder: r'C:\src',
    status: ImportBatchStatus.completed,
    discoveredCount: 5,
    importedCount: 4,
    duplicateCount: 0,
    failedCount: 1,
    pairedCount: 0,
    startedAt: DateTime.utc(2026, 6, id),
  );

  test('delegates to repository and returns the list unchanged', () async {
    final batches = [fakeBatch(1), fakeBatch(2)];
    final repo = FakeImportRepository(recentBatches: batches);
    final useCase = GetRecentImportBatchesUseCase(repo);

    final result = await useCase();

    expect(result, batches);
  });

  test('passes limit to repository', () async {
    final batches = List.generate(5, fakeBatch);
    final repo = FakeImportRepository(recentBatches: batches);
    final useCase = GetRecentImportBatchesUseCase(repo);

    final result = await useCase(limit: 3);

    expect(result, hasLength(3));
  });

  test('propagates exceptions from the repository', () async {
    final repo = FakeImportRepository(failGetRecentBatches: true);
    final useCase = GetRecentImportBatchesUseCase(repo);

    await expectLater(() => useCase(), throwsStateError);
  });
}
