import 'package:drift/drift.dart';

/// Shared shape for the simple bilingual reference tables (spec §11.2).
///
/// Each uses an English `snake_case` [key] as primary key plus required Arabic
/// and English display names, a sort order, and an active flag.
mixin BilingualReference on Table {
  TextColumn get key => text()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Languages extends Table with BilingualReference {
  @override
  String get tableName => 'languages';
}

class Countries extends Table with BilingualReference {
  @override
  String get tableName => 'countries';
}

class TrustLevels extends Table with BilingualReference {
  @override
  String get tableName => 'trust_levels';
}

class UsageRights extends Table with BilingualReference {
  @override
  String get tableName => 'usage_rights';
}

class MetadataQualities extends Table with BilingualReference {
  @override
  String get tableName => 'metadata_qualities';
}

class WorkflowStatuses extends Table with BilingualReference {
  @override
  String get tableName => 'workflow_statuses';
}

class FileRoles extends Table with BilingualReference {
  @override
  String get tableName => 'file_roles';
}

class FileHealthStatuses extends Table with BilingualReference {
  @override
  String get tableName => 'file_health_statuses';
}
