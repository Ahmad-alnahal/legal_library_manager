// lib/core/database/tables/related_file_candidates.dart

// The CHECK constraint references column getters, which the Dart analyzer reads
// as recursive even though drift_dev resolves them statically.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import 'document_files.dart';

/// Candidate pairs of physical files that may represent the same logical
/// document but cannot be detected by SHA-256 comparison (P2.4).
///
/// `file_a_id` is always less than `file_b_id` (enforced by a DB CHECK
/// constraint and canonicalised by the application layer before every insert).
/// `UNIQUE (file_a_id, file_b_id)` ensures idempotent upserts.
///
/// The generated Drift data class is named [RelatedFileCandidateRow] to avoid
/// a naming collision with the domain entity `RelatedFileCandidate`.
@DataClassName('RelatedFileCandidateRow')
@TableIndex(name: 'ix_rfc_file_a_id', columns: {#fileAId})
@TableIndex(name: 'ix_rfc_file_b_id', columns: {#fileBId})
@TableIndex(name: 'ix_rfc_status_key', columns: {#statusKey})
class RelatedFileCandidates extends Table {
  @override
  String get tableName => 'related_file_candidates';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get fileAId =>
      integer().references(DocumentFiles, #id, onDelete: KeyAction.restrict)();

  IntColumn get fileBId =>
      integer().references(DocumentFiles, #id, onDelete: KeyAction.restrict)();

  /// See `CandidateReason.key`.
  TextColumn get reasonKey => text()();

  /// Computed confidence score, [0.0, 1.0].
  RealColumn get confidence => real()();

  /// See `CandidateStatus.key`. Defaults to `'pending'`.
  TextColumn get statusKey => text().withDefault(const Constant('pending'))();

  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  /// Table-level constraints:
  ///   UNIQUE enforces idempotent upserts.
  ///   CHECK enforces canonical pair ordering (fileAId < fileBId).
  @override
  List<String> get customConstraints => [
    'UNIQUE (file_a_id, file_b_id)',
    'CHECK (file_a_id < file_b_id)',
  ];
}
