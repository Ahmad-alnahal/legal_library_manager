import 'package:drift/drift.dart';

import 'documents.dart';
import 'keywords.dart';

/// Many-to-many join between documents and keywords (spec §5.8).
///
/// Composite primary key `(document_id, keyword_id)`. Deleting a document
/// cascades its keyword links; a keyword cannot be deleted while still linked
/// (explicit `ON DELETE RESTRICT`).
@TableIndex(name: 'ix_document_keywords_keyword_id', columns: {#keywordId})
class DocumentKeywords extends Table {
  @override
  String get tableName => 'document_keywords';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get keywordId =>
      integer().references(Keywords, #id, onDelete: KeyAction.restrict)();
  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {documentId, keywordId};
}
