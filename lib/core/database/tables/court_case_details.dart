import 'package:drift/drift.dart';

import 'documents.dart';

/// Court-precedent-specific metadata (spec §6.5).
///
/// `document_id` is both primary key and FK to `documents.id`
/// (`ON DELETE CASCADE`). All fields are nullable for incomplete drafts.
class CourtCaseDetails extends Table {
  @override
  String get tableName => 'court_case_details';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get courtName => text().nullable()();
  TextColumn get caseNumber => text().nullable()();
  TextColumn get judgmentDate => text().nullable()();
  TextColumn get judgmentResult => text().nullable()();
  TextColumn get legalPrinciple => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  // WITHOUT ROWID so document_id is a real (required, NOT NULL) primary key
  // rather than a SQLite rowid alias that could be auto-generated when omitted.
  @override
  bool get withoutRowId => true;
}
