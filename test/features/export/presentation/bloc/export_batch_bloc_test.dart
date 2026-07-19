// test/features/export/presentation/bloc/export_batch_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_metadata_repository.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_batch_summary.dart';
import 'package:legal_library_manager/features/export/domain/entities/exportable_document_ref.dart';
import 'package:legal_library_manager/features/export/domain/entities/generate_export_batch_result.dart';
import 'package:legal_library_manager/features/export/domain/repositories/export_batch_repository.dart';
import 'package:legal_library_manager/features/export/presentation/bloc/export_batch_bloc.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';

class _FakeManagedCopyRepository implements ManagedCopyRepository {
  _FakeManagedCopyRepository({this.exportRoot});
  final String? exportRoot;

  @override
  Future<String?> loadExportRoot() async => exportRoot;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by ExportBatchBloc tests');
}

class _FakeMetadataRepository implements DocumentMetadataRepository {
  _FakeMetadataRepository(this.readyDocs);
  List<ExportableDocumentRef> readyDocs;

  @override
  Future<List<ExportableDocumentRef>> listReadyForExport() async => readyDocs;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by ExportBatchBloc tests');
}

class _FakeBatchRepository implements ExportBatchRepository {
  _FakeBatchRepository(this.batches);
  List<ExportBatchSummary> batches;

  @override
  Future<List<ExportBatchSummary>> listBatches() async => batches;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by ExportBatchBloc tests');
}

ExportableDocumentRef _ref(int id) => ExportableDocumentRef(
  id: id,
  documentCode: 'DOC-000$id',
  readyForExportAt: DateTime.utc(2026, 6, 1),
);

ExportBatchSummary _batch(String code) => ExportBatchSummary(
  id: 1,
  batchCode: code,
  exportPath: r'D:\Exports\batch',
  statusKey: 'verified',
  documentCount: 1,
  totalSizeBytes: 1024,
  createdAt: DateTime.utc(2026, 6, 1),
  completedAt: DateTime.utc(2026, 6, 1),
);

void main() {
  group('ExportBatchBloc', () {
    test('screen started loads root, count, and history', () async {
      final bloc = ExportBatchBloc.executor(
        managedCopyRepository: _FakeManagedCopyRepository(
          exportRoot: r'D:\Exports',
        ),
        metadataRepository: _FakeMetadataRepository([_ref(1), _ref(2)]),
        batchRepository: _FakeBatchRepository([_batch('EXP-2026-06-01-001')]),
        generate: () async => const GenerateExportBatchNothingToExport(),
      );

      final states = <ExportBatchState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ExportBatchScreenStarted());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.last.loadStatus, ExportBatchLoadStatus.ready);
      expect(states.last.exportRoot, r'D:\Exports');
      expect(states.last.readyForExportCount, 2);
      expect(states.last.batches.single.batchCode, 'EXP-2026-06-01-001');
      bloc.close();
    });

    test(
      'generate success emits running then success and reloads history/count',
      () async {
        final metadata = _FakeMetadataRepository([_ref(1)]);
        final batchRepo = _FakeBatchRepository([]);
        const result = GenerateExportBatchSuccess(
          batchCode: 'EXP-2026-06-01-001',
          exportPath: r'D:\Exports\batch',
          includedCount: 1,
          skippedCount: 0,
          skippedReasons: [],
          flaggedUsageRights: [],
        );
        final bloc = ExportBatchBloc.executor(
          managedCopyRepository: _FakeManagedCopyRepository(),
          metadataRepository: metadata,
          batchRepository: batchRepo,
          generate: () async {
            // Simulate generation reducing the ready count and adding history.
            metadata.readyDocs = [];
            batchRepo.batches = [_batch('EXP-2026-06-01-001')];
            return result;
          },
        );

        final states = <ExportBatchState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const ExportBatchGenerateRequested());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(states.first.isGenerating, isTrue);
        expect(states.first.generateStatus, ExportBatchGenerateStatus.running);
        final successState = states.firstWhere(
          (s) => s.generateStatus == ExportBatchGenerateStatus.success,
        );
        expect(successState.lastResult, result);
        expect(states.last.readyForExportCount, 0);
        expect(states.last.batches.single.batchCode, 'EXP-2026-06-01-001');
        expect(states.last.isGenerating, isFalse);
        bloc.close();
      },
    );

    test('generate nothingToExport emits the correct status', () async {
      final bloc = ExportBatchBloc.executor(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository([]),
        batchRepository: _FakeBatchRepository([]),
        generate: () async => const GenerateExportBatchNothingToExport(),
      );

      final states = <ExportBatchState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ExportBatchGenerateRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(
        states.any(
          (s) => s.generateStatus == ExportBatchGenerateStatus.nothingToExport,
        ),
        isTrue,
      );
      bloc.close();
    });

    test('overlapping guard ignores a second generate while running', () async {
      var callCount = 0;
      final bloc = ExportBatchBloc.executor(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository([]),
        batchRepository: _FakeBatchRepository([]),
        generate: () async {
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const GenerateExportBatchNothingToExport();
        },
      );

      bloc.add(const ExportBatchGenerateRequested());
      bloc.add(const ExportBatchGenerateRequested());

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(callCount, 1);
      bloc.close();
    });
  });
}
