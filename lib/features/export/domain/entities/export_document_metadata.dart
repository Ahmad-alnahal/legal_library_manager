// lib/features/export/domain/entities/export_document_metadata.dart

import 'package:equatable/equatable.dart';

import 'export_legislation_details.dart';
import 'export_legislation_relation.dart';

/// Website-safe export projection of one document's metadata.
///
/// Never includes local paths, the integer document id, audit events, import
/// history, duplicate info, related-file candidates, settings, security
/// fields, or managed-copy file paths.
class ExportDocumentMetadata extends Equatable {
  const ExportDocumentMetadata({
    required this.documentCode,
    required this.titleAr,
    required this.titleEn,
    required this.documentTypeKey,
    required this.documentTypeNameAr,
    required this.documentTypeNameEn,
    required this.primaryMainCategoryKey,
    required this.primaryMainCategoryNameAr,
    required this.primaryMainCategoryNameEn,
    required this.primarySubcategoryKey,
    required this.primarySubcategoryNameAr,
    required this.primarySubcategoryNameEn,
    required this.countryCode,
    required this.countryNameAr,
    required this.countryNameEn,
    required this.languageKey,
    required this.languageNameAr,
    required this.languageNameEn,
    required this.languageOther,
    required this.trustLevelKey,
    required this.usageRightsKey,
    required this.isUsageRightsFlagged,
    required this.metadataQualityKey,
    required this.summaryAr,
    required this.readyForExportAt,
    required this.keywords,
    required this.legislationDetails,
    required this.legislationRelations,
  });

  final String documentCode;
  final String? titleAr;
  final String? titleEn;
  final String documentTypeKey;
  final String documentTypeNameAr;
  final String documentTypeNameEn;
  final String primaryMainCategoryKey;
  final String primaryMainCategoryNameAr;
  final String primaryMainCategoryNameEn;
  final String? primarySubcategoryKey;
  final String? primarySubcategoryNameAr;
  final String? primarySubcategoryNameEn;
  final String? countryCode;
  final String? countryNameAr;
  final String? countryNameEn;
  final String? languageKey;
  final String? languageNameAr;
  final String? languageNameEn;
  final String? languageOther;
  final String trustLevelKey;
  final String usageRightsKey;
  final bool isUsageRightsFlagged;
  final String metadataQualityKey;
  final String? summaryAr;
  final DateTime readyForExportAt;
  final List<String> keywords;
  final ExportLegislationDetails? legislationDetails;
  final List<ExportLegislationRelation> legislationRelations;

  @override
  List<Object?> get props => [
    documentCode,
    titleAr,
    titleEn,
    documentTypeKey,
    documentTypeNameAr,
    documentTypeNameEn,
    primaryMainCategoryKey,
    primaryMainCategoryNameAr,
    primaryMainCategoryNameEn,
    primarySubcategoryKey,
    primarySubcategoryNameAr,
    primarySubcategoryNameEn,
    countryCode,
    countryNameAr,
    countryNameEn,
    languageKey,
    languageNameAr,
    languageNameEn,
    languageOther,
    trustLevelKey,
    usageRightsKey,
    isUsageRightsFlagged,
    metadataQualityKey,
    summaryAr,
    readyForExportAt,
    keywords,
    legislationDetails,
    legislationRelations,
  ];
}
