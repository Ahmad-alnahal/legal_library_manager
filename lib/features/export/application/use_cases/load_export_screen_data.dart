import '../../../documents/domain/repositories/document_metadata_repository.dart';
import '../../../managed_copy/domain/repositories/managed_copy_repository.dart';
import '../../domain/entities/export_screen_data.dart';
import '../../domain/repositories/export_batch_repository.dart';

class LoadExportScreenData {
  const LoadExportScreenData({
    required this._managedCopyRepository,
    required this._metadataRepository,
    required this._batchRepository,
  });

  final ManagedCopyRepository _managedCopyRepository;
  final DocumentMetadataRepository _metadataRepository;
  final ExportBatchRepository _batchRepository;

  Future<ExportScreenData> call() async {
    final (exportRoot, readyDocs, batches) = await (
      _managedCopyRepository.loadExportRoot(),
      _metadataRepository.listReadyForExport(),
      _batchRepository.listBatches(),
    ).wait;
    return ExportScreenData(
      exportRoot: exportRoot,
      readyForExportCount: readyDocs.length,
      batches: batches,
    );
  }
}
