// lib/features/export/domain/entities/export_eligibility_input.dart

import 'package:equatable/equatable.dart';

/// The minimal, focused set of fields needed to evaluate export eligibility
/// for one document — never the full document aggregate.
class ExportEligibilityInput extends Equatable {
  const ExportEligibilityInput({
    required this.workflowStatusKey,
    required this.hasHealthyManagedCopy,
    required this.primaryMainCategoryId,
    required this.primaryMainCategoryActive,
    this.primarySubCategoryId,
    this.primarySubCategoryActive,
    required this.metadataQualityKey,
    required this.usageRightsKey,
  });

  final String workflowStatusKey;
  final bool hasHealthyManagedCopy;
  final int? primaryMainCategoryId;
  final bool? primaryMainCategoryActive;
  final int? primarySubCategoryId;
  final bool? primarySubCategoryActive;
  final String metadataQualityKey;
  final String? usageRightsKey;

  @override
  List<Object?> get props => [
    workflowStatusKey,
    hasHealthyManagedCopy,
    primaryMainCategoryId,
    primaryMainCategoryActive,
    primarySubCategoryId,
    primarySubCategoryActive,
    metadataQualityKey,
    usageRightsKey,
  ];
}
