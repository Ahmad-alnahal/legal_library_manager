// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'documents.dart';
import 'main_categories.dart';
import 'sub_categories.dart';

/// Primary and additional legal classifications for a document (spec §5.6).
///
/// `document_id` cascades on document delete; the category references restrict.
/// `classification_role_key` accepts only `primary` or `additional`.
///
/// Combination uniqueness (including NULL subcategory) and the
/// one-primary-per-document rule are enforced by partial unique indexes created
/// in the database migration (drift's annotation indexes cannot carry a WHERE
/// clause).
@TableIndex(
  name: 'ix_document_classifications_document_id',
  columns: {#documentId},
)
@TableIndex(
  name: 'ix_document_classifications_main_sub',
  columns: {#mainCategoryId, #subCategoryId},
)
class DocumentClassifications extends Table {
  @override
  String get tableName => 'document_classifications';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get mainCategoryId =>
      integer().references(MainCategories, #id, onDelete: KeyAction.restrict)();
  IntColumn get subCategoryId => integer().nullable().references(
    SubCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  // CHECK (classification_role_key IN ('primary','additional')).
  TextColumn get classificationRoleKey => text().check(
    classificationRoleKey.isIn(const ['primary', 'additional']),
  )();
  TextColumn get createdAt => text()();
}
