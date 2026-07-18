// lib/features/export/domain/export_eligibility.dart

import 'entities/export_eligibility_input.dart';
import 'entities/export_eligibility_result.dart';

/// Pure export-eligibility check (workflow_and_validation_spec.md §10).
///
/// `copied_to_library -> ready_for_export` preconditions:
/// - managed copy exists and hash verification passes (a healthy
///   `managed_copy` file, checked upstream and summarized in
///   [ExportEligibilityInput.hasHealthyManagedCopy]);
/// - classification remains valid (an active primary main category, and an
///   active primary subcategory when one is set);
/// - metadata quality is `high` or `verified`;
/// - usage rights is explicitly reviewed and not `unknown`;
/// - the document is not archived.
///
/// No document-state I/O happens here; the repository loads only the fields
/// this function needs.
ExportEligibilityResult checkExportEligibility(ExportEligibilityInput input) {
  final List<String> reasons = [];

  if (input.workflowStatusKey == 'archived') {
    reasons.add('Document is archived.');
  } else if (input.workflowStatusKey != 'copied_to_library') {
    reasons.add(
      'Document must be copied_to_library before it can be marked '
      'ready_for_export.',
    );
  }

  if (!input.hasHealthyManagedCopy) {
    reasons.add('Document has no healthy managed-copy file.');
  }

  if (input.primaryMainCategoryId == null ||
      input.primaryMainCategoryActive != true) {
    reasons.add('Document has no active primary classification.');
  } else if (input.primarySubCategoryId != null &&
      input.primarySubCategoryActive != true) {
    reasons.add('Document primary subcategory is not active.');
  }

  if (input.metadataQualityKey != 'high' &&
      input.metadataQualityKey != 'verified') {
    reasons.add('Metadata quality must be high or verified.');
  }

  if (input.usageRightsKey == null || input.usageRightsKey == 'unknown') {
    reasons.add('Usage rights must be explicitly reviewed.');
  }

  if (reasons.isEmpty) return const ExportEligible();
  return ExportIneligible(reasons);
}
