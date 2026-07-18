// lib/features/export/application/use_cases/mark_document_ready_for_export.dart

import '../../../../core/time/clock.dart';
import '../../../documents/domain/repositories/document_metadata_repository.dart';
import '../../domain/entities/export_eligibility_result.dart';
import '../../domain/entities/mark_ready_for_export_result.dart';

/// Transitions a document from `copied_to_library` to `ready_for_export`
/// (workflow_and_validation_spec.md §10).
///
/// Loads only the focused eligibility fields (never the full aggregate). When
/// ineligible, returns the violated rules and changes nothing. When eligible,
/// performs the transactional transition.
///
/// P3.1 filter-support finding: `DocumentListFilters.workflowStatusKey`
/// (documents/domain/entities/document_list_query.dart) is a plain string
/// equality filter, not an enum — it already supports filtering the document
/// list by `workflow_status_key == 'ready_for_export'` with no code change.
class MarkDocumentReadyForExport {
  MarkDocumentReadyForExport({required this.repository, required this.clock});

  final DocumentMetadataRepository repository;
  final Clock clock;

  Future<MarkReadyForExportResult> call(int documentId) async {
    final ExportEligibilityResult eligibility = await repository
        .checkExportEligibility(documentId);

    switch (eligibility) {
      case ExportIneligible(:final reasons):
        return MarkReadyForExportIneligible(reasons);
      case ExportEligible():
        await repository.markReadyForExport(documentId, now: clock.nowUtc());
        return const MarkReadyForExportSuccess();
    }
  }
}
