// lib/features/export/domain/entities/mark_ready_for_export_result.dart

/// Sealed result of [MarkDocumentReadyForExport].
sealed class MarkReadyForExportResult {
  const MarkReadyForExportResult();
}

/// The document was successfully transitioned to `ready_for_export`.
final class MarkReadyForExportSuccess extends MarkReadyForExportResult {
  const MarkReadyForExportSuccess();
}

/// The document failed one or more export-eligibility rules; nothing changed.
final class MarkReadyForExportIneligible extends MarkReadyForExportResult {
  const MarkReadyForExportIneligible(this.reasons);

  final List<String> reasons;
}
