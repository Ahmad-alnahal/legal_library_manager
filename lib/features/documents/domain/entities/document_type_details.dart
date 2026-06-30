// lib/features/documents/domain/entities/document_type_details.dart

import 'package:equatable/equatable.dart';

/// Type-specific detail metadata for a document.
///
/// A sealed hierarchy: exactly one variant matches the document's selected type.
/// The `other` type has no detail variant — it is represented by a `null`
/// details object and uses the common fields plus review notes.
///
/// [documentTypeKey] is the stable document-type key this detail belongs to;
/// the repository persists a detail only into the table matching that key, and
/// validation rejects a detail whose key does not match the selected type.
sealed class DocumentTypeDetails extends Equatable {
  const DocumentTypeDetails();

  String get documentTypeKey;
}

/// Book detail metadata (spec §6.1).
class BookDetailsData extends DocumentTypeDetails {
  const BookDetailsData({this.author, this.publisher, this.publicationPlace});

  final String? author;
  final String? publisher;
  final String? publicationPlace;

  @override
  String get documentTypeKey => 'book';

  @override
  List<Object?> get props => [author, publisher, publicationPlace];
}

/// Thesis detail metadata (spec §6.2).
class ThesisDetailsData extends DocumentTypeDetails {
  const ThesisDetailsData({
    this.researcherName,
    this.degreeTypeKey,
    this.universityName,
    this.supervisorName,
  });

  final String? researcherName;
  final String? degreeTypeKey;
  final String? universityName;
  final String? supervisorName;

  @override
  String get documentTypeKey => 'thesis';

  @override
  List<Object?> get props => [
    researcherName,
    degreeTypeKey,
    universityName,
    supervisorName,
  ];
}

/// Research-paper detail metadata (spec §6.3).
class ResearchDetailsData extends DocumentTypeDetails {
  const ResearchDetailsData({
    this.researcherName,
    this.journalName,
    this.publishingEntity,
    this.volume,
    this.issue,
  });

  final String? researcherName;
  final String? journalName;
  final String? publishingEntity;
  final String? volume;
  final String? issue;

  @override
  String get documentTypeKey => 'research_paper';

  @override
  List<Object?> get props => [
    researcherName,
    journalName,
    publishingEntity,
    volume,
    issue,
  ];
}

/// Legislation detail metadata (spec §6.4, extended in schema v6).
class LegislationDetailsData extends DocumentTypeDetails {
  const LegislationDetailsData({
    this.legislationTypeKey,
    this.legislationTypeOther,
    this.effectiveStatusKey,
    this.issueNumber,
    this.publicationDate,
    this.legislationNumber,
    this.legislationYear,
    this.effectiveDate,
    this.repealDate,
  });

  final String? legislationTypeKey;
  final String? legislationTypeOther;
  final String? effectiveStatusKey;
  final String? issueNumber;
  final String? publicationDate;

  // v6 additions.
  final String? legislationNumber;
  final int? legislationYear;
  final String? effectiveDate;
  final String? repealDate;

  @override
  String get documentTypeKey => 'legislation';

  @override
  List<Object?> get props => [
    legislationTypeKey,
    legislationTypeOther,
    effectiveStatusKey,
    issueNumber,
    publicationDate,
    legislationNumber,
    legislationYear,
    effectiveDate,
    repealDate,
  ];
}

/// Court-precedent detail metadata (spec §6.5).
class CourtCaseDetailsData extends DocumentTypeDetails {
  const CourtCaseDetailsData({
    this.courtName,
    this.caseNumber,
    this.judgmentDate,
    this.judgmentResult,
    this.legalPrinciple,
  });

  final String? courtName;
  final String? caseNumber;
  final String? judgmentDate;
  final String? judgmentResult;
  final String? legalPrinciple;

  @override
  String get documentTypeKey => 'court_precedent';

  @override
  List<Object?> get props => [
    courtName,
    caseNumber,
    judgmentDate,
    judgmentResult,
    legalPrinciple,
  ];
}

/// Institutional-report detail metadata (spec §6.6).
class ReportDetailsData extends DocumentTypeDetails {
  const ReportDetailsData({this.publishingEntity});

  final String? publishingEntity;

  @override
  String get documentTypeKey => 'institutional_report';

  @override
  List<Object?> get props => [publishingEntity];
}
