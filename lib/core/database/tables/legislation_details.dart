// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'documents.dart';

/// Legislation-specific metadata (spec §6.4, extended in schema v6).
///
/// `document_id` is both primary key and FK to `documents.id`
/// (`ON DELETE CASCADE`). All fields are nullable for incomplete drafts.
///
/// Schema v6 additions:
/// - legislation_number TEXT nullable
/// - legislation_year INTEGER nullable
/// - effective_date TEXT nullable
/// - repeal_date TEXT nullable
/// - effective_status_key expanded to include 'amended' and 'expired'
///
/// Schema v7 addition:
/// - legislation_type_other TEXT nullable, required by validation when
///   legislation_type_key is 'other'
class LegislationDetails extends Table {
  @override
  String get tableName => 'legislation_details';

  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();

  TextColumn get legislationTypeKey => text().nullable().check(
    legislationTypeKey.isIn(const [
      'ordinary_legislation',
      'regulation',
      'executive_regulation',
      'other',
    ]),
  )();

  TextColumn get legislationTypeOther => text().nullable()();

  TextColumn get effectiveStatusKey => text().nullable().check(
    effectiveStatusKey.isIn(const [
      'active',
      'repealed',
      'amended',
      'expired',
      'unknown',
    ]),
  )();

  TextColumn get issueNumber => text().nullable()();
  TextColumn get publicationDate => text().nullable()();

  // v6 additions — nullable so all existing rows remain valid after migration.
  TextColumn get legislationNumber => text().nullable()();
  IntColumn get legislationYear => integer().nullable()();
  TextColumn get effectiveDate => text().nullable()();
  TextColumn get repealDate => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  // WITHOUT ROWID so document_id is a real (required, NOT NULL) primary key
  // rather than a SQLite rowid alias that could be auto-generated when omitted.
  @override
  bool get withoutRowId => true;
}
