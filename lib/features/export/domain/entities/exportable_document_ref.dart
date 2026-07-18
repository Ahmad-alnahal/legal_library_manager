// lib/features/export/domain/entities/exportable_document_ref.dart

import 'package:equatable/equatable.dart';

/// A minimal reference to a `ready_for_export` document, used by P3.3 batch
/// generation to select which documents to package.
class ExportableDocumentRef extends Equatable {
  const ExportableDocumentRef({
    required this.id,
    required this.documentCode,
    required this.readyForExportAt,
  });

  final int id;
  final String documentCode;
  final DateTime readyForExportAt;

  @override
  List<Object?> get props => [id, documentCode, readyForExportAt];
}
