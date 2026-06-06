import 'package:drift/drift.dart';

import 'documents.dart';

/// Institutional-report-specific metadata (spec §6.6).
///
/// `document_id` is both primary key and FK to `documents.id`
/// (`ON DELETE CASCADE`). The field is nullable for incomplete drafts.
class ReportDetails extends Table {
  @override
  String get tableName => 'report_details';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get publishingEntity => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  // WITHOUT ROWID so document_id is a real (required, NOT NULL) primary key
  // rather than a SQLite rowid alias that could be auto-generated when omitted.
  @override
  bool get withoutRowId => true;
}
