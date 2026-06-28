// lib/features/related_files/domain/entities/related_file_review_row.dart

import 'package:equatable/equatable.dart';

import 'candidate_reason.dart';

/// Read-model for the review queue. Carries enriched file + document metadata
/// from a JOIN across related_file_candidates → document_files → documents.
///
/// Immutable — never mutated; rebuilt on each reload.
class RelatedFileReviewRow extends Equatable {
  const RelatedFileReviewRow({
    required this.candidateId,
    required this.confidence,
    required this.reason,
    required this.createdAt,
    required this.fileAId,
    required this.fileAName,
    required this.fileAPath,
    required this.fileAExtension,
    required this.documentAId,
    required this.documentATitle,
    required this.documentACode,
    required this.documentAWorkflowStatus,
    required this.fileBId,
    required this.fileBName,
    required this.fileBPath,
    required this.fileBExtension,
    required this.documentBId,
    required this.documentBTitle,
    required this.documentBCode,
    required this.documentBWorkflowStatus,
  });

  final int candidateId;
  final double confidence;
  final CandidateReason reason;
  final DateTime createdAt;

  // File A (always file_a_id < file_b_id per DB CHECK constraint)
  final int fileAId;
  final String fileAName;
  final String fileAPath;
  final String fileAExtension;
  final int documentAId;
  final String? documentATitle;
  final String? documentACode;
  final String? documentAWorkflowStatus;

  // File B
  final int fileBId;
  final String fileBName;
  final String fileBPath;
  final String fileBExtension;
  final int documentBId;
  final String? documentBTitle;
  final String? documentBCode;
  final String? documentBWorkflowStatus;

  @override
  List<Object?> get props => [
    candidateId,
    confidence,
    reason,
    createdAt,
    fileAId,
    fileAName,
    fileAPath,
    fileAExtension,
    documentAId,
    documentATitle,
    documentACode,
    documentAWorkflowStatus,
    fileBId,
    fileBName,
    fileBPath,
    fileBExtension,
    documentBId,
    documentBTitle,
    documentBCode,
    documentBWorkflowStatus,
  ];
}
