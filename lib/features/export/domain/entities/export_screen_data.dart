import 'export_batch_summary.dart';

class ExportScreenData {
  const ExportScreenData({
    required this.exportRoot,
    required this.readyForExportCount,
    required this.batches,
  });

  final String? exportRoot;
  final int readyForExportCount;
  final List<ExportBatchSummary> batches;
}
