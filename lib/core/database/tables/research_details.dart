import 'package:drift/drift.dart';

import 'documents.dart';

/// Research-paper-specific metadata (spec §6.3).
///
/// `document_id` is both primary key and FK to `documents.id`
/// (`ON DELETE CASCADE`). All fields are nullable for incomplete drafts.
class ResearchDetails extends Table {
  @override
  String get tableName => 'research_details';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get researcherName => text().nullable()();
  TextColumn get journalName => text().nullable()();
  TextColumn get publishingEntity => text().nullable()();
  TextColumn get volume => text().nullable()();
  TextColumn get issue => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  // WITHOUT ROWID so document_id is a real (required, NOT NULL) primary key
  // rather than a SQLite rowid alias that could be auto-generated when omitted.
  @override
  bool get withoutRowId => true;
}
