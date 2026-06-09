import '../entities/document_list_item.dart';
import '../entities/document_list_query.dart';

abstract class DocumentListRepository {
  Future<DocumentListPage> getDocuments(DocumentListQuery query);

  Future<List<DocumentSourceFileItem>> getSourceFiles(int documentId);
}
