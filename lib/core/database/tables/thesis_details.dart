// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'documents.dart';

/// Thesis-specific metadata (spec §6.2).
///
/// `document_id` is both primary key and FK to `documents.id`
/// (`ON DELETE CASCADE`). All fields are nullable for incomplete drafts.
/// `degree_type_key`, when set, must be one of `masters`, `doctorate`, `other`;
/// the CHECK still allows NULL (SQLite treats `NULL IN (...)` as not-false).
class ThesisDetails extends Table {
  @override
  String get tableName => 'thesis_details';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get researcherName => text().nullable()();
  // CHECK (degree_type_key IN ('masters','doctorate','other')) — NULL allowed.
  TextColumn get degreeTypeKey => text().nullable().check(
    degreeTypeKey.isIn(const ['masters', 'doctorate', 'other']),
  )();
  TextColumn get universityName => text().nullable()();
  TextColumn get supervisorName => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  // WITHOUT ROWID so document_id is a real (required, NOT NULL) primary key
  // rather than a SQLite rowid alias that could be auto-generated when omitted.
  @override
  bool get withoutRowId => true;
}
