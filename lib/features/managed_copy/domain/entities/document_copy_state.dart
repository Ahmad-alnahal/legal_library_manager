// lib/features/managed_copy/domain/entities/document_copy_state.dart

/// Minimal document information needed to validate a managed-copy request.
class DocumentCopyState {
  const DocumentCopyState({
    required this.documentId,
    required this.workflowStatusKey,
    required this.existingDocumentCode,
    required this.hasManagedCopy,
    required this.hasHealthyManagedCopy,
  });

  final int documentId;

  /// The current workflow status key stored in the documents table.
  final String workflowStatusKey;

  /// The existing document_code, or null if not yet assigned.
  final String? existingDocumentCode;

  /// True when at least one document_files row with role 'managed_copy' exists
  /// for this document (regardless of health state).
  final bool hasManagedCopy;

  /// True when at least one managed-copy row has file_health_key != 'missing'.
  ///
  /// Used by [ManagedCopyUseCase] to block re-copy when a healthy copy exists.
  /// A document whose only managed copies are all marked 'missing' is eligible
  /// for re-copy after user-initiated reconciliation (M8.6).
  final bool hasHealthyManagedCopy;
}
