// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'documents.dart';

/// Legislation-specific metadata (spec §6.4).
///
/// `document_id` is both primary key and FK to `documents.id`
/// (`ON DELETE CASCADE`). All fields are nullable for incomplete drafts. The
/// constrained keys allow NULL but otherwise restrict to the listed values.
class LegislationDetails extends Table {
  @override
  String get tableName => 'legislation_details';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  // CHECK legislation_type_key IN
  // ('ordinary_legislation','regulation','executive_regulation','other').
  TextColumn get legislationTypeKey => text().nullable().check(
    legislationTypeKey.isIn(const [
      'ordinary_legislation',
      'regulation',
      'executive_regulation',
      'other',
    ]),
  )();
  // CHECK (effective_status_key IN ('active','repealed','unknown')).
  TextColumn get effectiveStatusKey => text().nullable().check(
    effectiveStatusKey.isIn(const ['active', 'repealed', 'unknown']),
  )();
  TextColumn get issueNumber => text().nullable()();
  TextColumn get publicationDate => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  // WITHOUT ROWID so document_id is a real (required, NOT NULL) primary key
  // rather than a SQLite rowid alias that could be auto-generated when omitted.
  @override
  bool get withoutRowId => true;
}
