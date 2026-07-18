// lib/features/export/domain/entities/export_batch_summary.dart

import 'package:equatable/equatable.dart';

/// Summary of one `export_batches` row.
class ExportBatchSummary extends Equatable {
  const ExportBatchSummary({
    required this.id,
    required this.batchCode,
    required this.exportPath,
    required this.statusKey,
    required this.documentCount,
    required this.totalSizeBytes,
    required this.createdAt,
    required this.completedAt,
  });

  final int id;
  final String batchCode;
  final String exportPath;
  final String statusKey;
  final int documentCount;
  final int totalSizeBytes;
  final DateTime createdAt;
  final DateTime? completedAt;

  @override
  List<Object?> get props => [
    id,
    batchCode,
    exportPath,
    statusKey,
    documentCount,
    totalSizeBytes,
    createdAt,
    completedAt,
  ];
}
