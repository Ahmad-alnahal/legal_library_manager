import '../entities/document_list_item.dart';
import '../entities/document_list_query.dart';

abstract class DocumentListRepository {
  Future<DocumentListPage> getDocuments(DocumentListQuery query);

  Future<List<DocumentSourceFileItem>> getSourceFiles(int documentId);

  /// Marks one healthy PDF source as the preferred source for [documentId].
  ///
  /// This updates database metadata only. It never changes the source file.
  Future<void> setPreferredSourceFile(int documentId, int fileId) =>
      throw UnimplementedError(
        'Preferred-source selection is not implemented.',
      );
}
