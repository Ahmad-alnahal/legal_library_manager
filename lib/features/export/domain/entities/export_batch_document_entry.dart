// lib/features/export/domain/entities/export_batch_document_entry.dart

import 'package:equatable/equatable.dart';

/// One document snapshot row to insert into `export_batch_documents`.
class ExportBatchDocumentEntry extends Equatable {
  const ExportBatchDocumentEntry({
    required this.batchId,
    required this.documentId,
    required this.managedFileId,
    required this.sha256Hash,
    required this.createdAt,
  });

  final int batchId;
  final int documentId;
  final int managedFileId;
  final String sha256Hash;
  final DateTime createdAt;

  @override
  List<Object?> get props => [
    batchId,
    documentId,
    managedFileId,
    sha256Hash,
    createdAt,
  ];
}
