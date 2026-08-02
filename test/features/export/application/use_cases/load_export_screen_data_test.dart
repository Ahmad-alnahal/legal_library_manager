import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_metadata_repository.dart';
import 'package:legal_library_manager/features/export/application/use_cases/load_export_screen_data.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_batch_summary.dart';
import 'package:legal_library_manager/features/export/domain/entities/exportable_document_ref.dart';
import 'package:legal_library_manager/features/export/domain/repositories/export_batch_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';

class _FakeManagedCopyRepository implements ManagedCopyRepository {
  _FakeManagedCopyRepository({this.exportRoot});
  final String? exportRoot;
  @override
  Future<String?> loadExportRoot() async => exportRoot;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeMetadataRepository implements DocumentMetadataRepository {
  _FakeMetadataRepository(this._docs);
  final List<ExportableDocumentRef> _docs;
  @override
  Future<List<ExportableDocumentRef>> listReadyForExport() async => _docs;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeBatchRepository implements ExportBatchRepository {
  _FakeBatchRepository(this._batches);
  final List<ExportBatchSummary> _batches;
  @override
  Future<List<ExportBatchSummary>> listBatches() async => _batches;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
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
  statusKey: ExportBatchStatusKey.verified,
  documentCount: 1,
  totalSizeBytes: 1024,
  createdAt: DateTime.utc(2026, 6, 1),
  completedAt: DateTime.utc(2026, 6, 1),
);

void main() {
  group('LoadExportScreenData', () {
    test('returns exportRoot from managedCopyRepository', () async {
      final useCase = LoadExportScreenData(
        managedCopyRepository: _FakeManagedCopyRepository(
          exportRoot: r'D:\Exports',
        ),
        metadataRepository: _FakeMetadataRepository(const []),
        batchRepository: _FakeBatchRepository(const []),
      );

      final result = await useCase();

      expect(result.exportRoot, r'D:\Exports');
    });

    test('returns null exportRoot when not configured', () async {
      final useCase = LoadExportScreenData(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository(const []),
        batchRepository: _FakeBatchRepository(const []),
      );

      final result = await useCase();

      expect(result.exportRoot, isNull);
    });

    test('readyForExportCount equals number of ready documents', () async {
      final useCase = LoadExportScreenData(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository([
          _ref(1),
          _ref(2),
          _ref(3),
        ]),
        batchRepository: _FakeBatchRepository(const []),
      );

      final result = await useCase();

      expect(result.readyForExportCount, 3);
    });

    test('readyForExportCount is zero when no documents are ready', () async {
      final useCase = LoadExportScreenData(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository(const []),
        batchRepository: _FakeBatchRepository(const []),
      );

      final result = await useCase();

      expect(result.readyForExportCount, 0);
    });

    test('batches list is populated from batchRepository', () async {
      final useCase = LoadExportScreenData(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository(const []),
        batchRepository: _FakeBatchRepository([
          _batch('EXP-2026-06-01-001'),
          _batch('EXP-2026-06-01-002'),
        ]),
      );

      final result = await useCase();

      expect(result.batches.length, 2);
      expect(result.batches.first.batchCode, 'EXP-2026-06-01-001');
    });

    test('batches list is empty when no batches exist', () async {
      final useCase = LoadExportScreenData(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository(const []),
        batchRepository: _FakeBatchRepository(const []),
      );

      final result = await useCase();

      expect(result.batches, isEmpty);
    });
  });
}
