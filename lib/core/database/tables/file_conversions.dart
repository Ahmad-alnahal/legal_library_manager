// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'document_files.dart';
import 'documents.dart';

/// Tracks future Word-to-PDF derivative generation (spec §8.1).
///
/// All three file/document references use `ON DELETE RESTRICT`. `status_key` is
/// required and constrained to the documented status keys. Error fields are
/// nullable and, by policy, must never store document contents.
class FileConversions extends Table {
  @override
  String get tableName => 'file_conversions';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.restrict)();
  IntColumn get sourceFileId =>
      integer().references(DocumentFiles, #id, onDelete: KeyAction.restrict)();
  IntColumn get outputFileId => integer().nullable().references(
    DocumentFiles,
    #id,
    onDelete: KeyAction.restrict,
  )();
  // CHECK status_key IN (...the seven documented conversion statuses...).
  TextColumn get statusKey => text().check(
    statusKey.isIn(const [
      'not_required',
      'pending_conversion',
      'converting',
      'conversion_succeeded',
      'needs_conversion_review',
      'conversion_failed',
      'conversion_approved',
    ]),
  )();
  TextColumn get converterKey => text().nullable()();
  TextColumn get converterVersion => text().nullable()();
  TextColumn get startedAt => text().nullable()();
  TextColumn get completedAt => text().nullable()();
  TextColumn get qualityReviewedAt => text().nullable()();
  BoolColumn get qualityApproved => boolean().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessageSafe => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
}
