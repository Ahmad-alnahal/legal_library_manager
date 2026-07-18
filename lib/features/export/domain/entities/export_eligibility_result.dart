// lib/features/export/domain/entities/export_eligibility_result.dart

/// Sealed result of evaluating whether a document may transition
/// `copied_to_library -> ready_for_export`
/// (workflow_and_validation_spec.md §10).
sealed class ExportEligibilityResult {
  const ExportEligibilityResult();
}

/// The document satisfies every export-eligibility rule.
final class ExportEligible extends ExportEligibilityResult {
  const ExportEligible();
}

/// The document fails at least one export-eligibility rule. [reasons] lists
/// every violated rule, not just the first — callers should show the full set.
final class ExportIneligible extends ExportEligibilityResult {
  const ExportIneligible(this.reasons);

  final List<String> reasons;
}
