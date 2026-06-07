// lib/features/documents/domain/entities/document_common_metadata.dart

import 'package:equatable/equatable.dart';

/// User-entered common metadata for a document (spec §5.1), independent of
/// document type. Primary main/sub categories are NOT part of this object —
/// they are derived from the primary classification and synchronized by the
/// repository.
///
/// All fields are nullable because drafts may be incomplete.
class DocumentCommonMetadata extends Equatable {
  const DocumentCommonMetadata({
    this.documentTypeId,
    this.title,
    this.languageKey,
    this.countryKey,
    this.publicationYear,
    this.summary,
    this.sourceDescription,
    this.trustLevelKey,
    this.usageRightsKey,
    this.metadataQualityKey,
    this.reviewNotes,
  });

  final int? documentTypeId;
  final String? title;
  final String? languageKey;
  final String? countryKey;
  final int? publicationYear;
  final String? summary;
  final String? sourceDescription;
  final String? trustLevelKey;
  final String? usageRightsKey;
  final String? metadataQualityKey;
  final String? reviewNotes;

  DocumentCommonMetadata copyWith({
    int? documentTypeId,
    String? title,
    String? languageKey,
    String? countryKey,
    int? publicationYear,
    String? summary,
    String? sourceDescription,
    String? trustLevelKey,
    String? usageRightsKey,
    String? metadataQualityKey,
    String? reviewNotes,
  }) {
    return DocumentCommonMetadata(
      documentTypeId: documentTypeId ?? this.documentTypeId,
      title: title ?? this.title,
      languageKey: languageKey ?? this.languageKey,
      countryKey: countryKey ?? this.countryKey,
      publicationYear: publicationYear ?? this.publicationYear,
      summary: summary ?? this.summary,
      sourceDescription: sourceDescription ?? this.sourceDescription,
      trustLevelKey: trustLevelKey ?? this.trustLevelKey,
      usageRightsKey: usageRightsKey ?? this.usageRightsKey,
      metadataQualityKey: metadataQualityKey ?? this.metadataQualityKey,
      reviewNotes: reviewNotes ?? this.reviewNotes,
    );
  }

  @override
  List<Object?> get props => [
    documentTypeId,
    title,
    languageKey,
    countryKey,
    publicationYear,
    summary,
    sourceDescription,
    trustLevelKey,
    usageRightsKey,
    metadataQualityKey,
    reviewNotes,
  ];
}
