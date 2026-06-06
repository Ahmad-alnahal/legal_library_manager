// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'document_types.dart';
import 'main_categories.dart';
import 'reference_tables.dart';
import 'sub_categories.dart';

/// Logical legal/catalog record and user-entered common metadata (spec §5.1).
///
/// All reference columns are foreign keys with `ON DELETE RESTRICT` (spec §13).
/// Reference defaults: trust=`unverified`, usage=`unknown`, quality=`low`,
/// status=`imported`. `publication_year` is constrained to a sensible range.
@TableIndex(
  name: 'ux_documents_document_code',
  columns: {#documentCode},
  unique: true,
)
@TableIndex(
  name: 'ix_documents_workflow_status_key',
  columns: {#workflowStatusKey},
)
@TableIndex(name: 'ix_documents_document_type_id', columns: {#documentTypeId})
@TableIndex(
  name: 'ix_documents_primary_main_category_id',
  columns: {#primaryMainCategoryId},
)
@TableIndex(
  name: 'ix_documents_primary_sub_category_id',
  columns: {#primarySubCategoryId},
)
@TableIndex(name: 'ix_documents_publication_year', columns: {#publicationYear})
@TableIndex(name: 'ix_documents_country_key', columns: {#countryKey})
@TableIndex(name: 'ix_documents_trust_level_key', columns: {#trustLevelKey})
@TableIndex(
  name: 'ix_documents_metadata_quality_key',
  columns: {#metadataQualityKey},
)
@TableIndex(name: 'ix_documents_updated_at', columns: {#updatedAt})
class Documents extends Table {
  @override
  String get tableName => 'documents';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get documentCode => text().nullable()();
  IntColumn get documentTypeId => integer().nullable().references(
    DocumentTypes,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get title => text().nullable()();
  IntColumn get primaryMainCategoryId => integer().nullable().references(
    MainCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get primarySubCategoryId => integer().nullable().references(
    SubCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get languageKey => text().nullable().references(
    Languages,
    #key,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get countryKey => text().nullable().references(
    Countries,
    #key,
    onDelete: KeyAction.restrict,
  )();
  // CHECK (publication_year BETWEEN 1000 AND 2100). drift_dev resolves the
  // column reference statically; the getter is never executed at runtime.
  IntColumn get publicationYear =>
      integer().nullable().check(publicationYear.isBetweenValues(1000, 2100))();
  TextColumn get summary => text().nullable()();
  TextColumn get sourceDescription => text().nullable()();
  TextColumn get trustLevelKey => text()
      .references(TrustLevels, #key, onDelete: KeyAction.restrict)
      .withDefault(const Constant('unverified'))();
  TextColumn get usageRightsKey => text()
      .references(UsageRights, #key, onDelete: KeyAction.restrict)
      .withDefault(const Constant('unknown'))();
  TextColumn get metadataQualityKey => text()
      .references(MetadataQualities, #key, onDelete: KeyAction.restrict)
      .withDefault(const Constant('low'))();
  TextColumn get workflowStatusKey => text()
      .references(WorkflowStatuses, #key, onDelete: KeyAction.restrict)
      .withDefault(const Constant('imported'))();
  TextColumn get reviewNotes => text().nullable()();
  TextColumn get classifiedAt => text().nullable()();
  TextColumn get copiedToLibraryAt => text().nullable()();
  TextColumn get readyForExportAt => text().nullable()();
  TextColumn get archivedAt => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
}
