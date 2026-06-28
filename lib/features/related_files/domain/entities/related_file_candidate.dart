// lib/features/related_files/domain/entities/related_file_candidate.dart

import 'package:equatable/equatable.dart';

import 'candidate_reason.dart';
import 'candidate_status.dart';

/// A persisted related-file candidate row loaded from the database.
///
/// [fileAId] is always less than [fileBId] (canonical ordering enforced by the
/// DB CHECK constraint and the application layer). No Drift types leak here.
class RelatedFileCandidate extends Equatable {
  const RelatedFileCandidate({
    required this.id,
    required this.fileAId,
    required this.fileBId,
    required this.reason,
    required this.confidence,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;

  /// Always less than [fileBId].
  final int fileAId;
  final int fileBId;
  final CandidateReason reason;

  /// Computed confidence score in [0.0, 1.0].
  final double confidence;
  final CandidateStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
    id,
    fileAId,
    fileBId,
    reason,
    confidence,
    status,
    createdAt,
    updatedAt,
  ];
}
