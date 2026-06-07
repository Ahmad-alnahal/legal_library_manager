// lib/features/documents/domain/entities/document_conversion_ref.dart

import 'package:equatable/equatable.dart';

/// Minimal, read-only view of a file-conversion record — only the fields needed
/// to decide whether a `converted_pdf` output file is approved for use.
class DocumentConversionRef extends Equatable {
  const DocumentConversionRef({
    required this.statusKey,
    this.outputFileId,
    this.qualityApproved,
  });

  final String statusKey;
  final int? outputFileId;
  final bool? qualityApproved;

  /// A conversion counts as approved only when its status is exactly
  /// `conversion_approved`. [qualityApproved] alone never makes a failed,
  /// pending, converting, or review-needed conversion acceptable.
  bool get isApproved => statusKey == 'conversion_approved';

  @override
  List<Object?> get props => [statusKey, outputFileId, qualityApproved];
}
