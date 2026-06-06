import 'package:drift/drift.dart';

import 'documents.dart';

/// Book-specific metadata (spec §6.1).
///
/// `document_id` is both the primary key and the FK to `documents.id`
/// (`ON DELETE CASCADE`), so a document has at most one book-details row. All
/// metadata fields are nullable because drafts may be incomplete.
class BookDetails extends Table {
  @override
  String get tableName => 'book_details';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get author => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get publicationPlace => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  // WITHOUT ROWID so document_id is a real (required, NOT NULL) primary key
  // rather than a SQLite rowid alias that could be auto-generated when omitted.
  @override
  bool get withoutRowId => true;
}
