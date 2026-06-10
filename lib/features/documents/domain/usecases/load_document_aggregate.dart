// lib/features/documents/domain/usecases/load_document_aggregate.dart

import '../entities/document_aggregate.dart';
import '../repositories/document_metadata_repository.dart';

/// Loads the complete, persistence-agnostic metadata aggregate for one document
/// so it can be reviewed/edited.
///
/// Returns the [DocumentAggregate], or `null` when the document does not exist —
/// a clear, explicit not-found signal the caller (the review BLoC) maps to a
/// not-found state. Reads only; never mutates anything.
class LoadDocumentAggregate {
  LoadDocumentAggregate(this.repository);

  final DocumentMetadataRepository repository;

  Future<DocumentAggregate?> call(int documentId) =>
      repository.loadAggregate(documentId);
}
