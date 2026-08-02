abstract final class WorkflowStatusKey {
  static const String imported = 'imported';
  static const String needsReview = 'needs_review';
  static const String inProgress = 'in_progress';
  static const String classified = 'classified';
  static const String copiedToLibrary = 'copied_to_library';
  static const String readyForExport = 'ready_for_export';
  static const String archived = 'archived';
}

abstract final class FileRoleKey {
  static const String sourceOriginal = 'source_original';
  static const String managedCopy = 'managed_copy';
  static const String convertedPdf = 'converted_pdf';
  static const String exportCopy = 'export_copy';
}

abstract final class FileHealthKey {
  static const String unknown = 'unknown';
  static const String healthy = 'healthy';
  static const String corrupted = 'corrupted';
  static const String unreadable = 'unreadable';
  static const String missing = 'missing';
}

abstract final class TrustLevelKey {
  static const String trusted = 'trusted';
  static const String medium = 'medium';
  static const String unverified = 'unverified';
}

abstract final class UsageRightsKey {
  static const String unknown = 'unknown';
  static const String personalUseOnly = 'personal_use_only';
  static const String publishable = 'publishable';
  static const String openAccess = 'open_access';
  static const String permissionRequired = 'permission_required';
}

abstract final class MetadataQualityKey {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';
  static const String verified = 'verified';
}

abstract final class ExportBatchStatusKey {
  static const String preparing = 'preparing';
  static const String completed = 'completed';
  static const String failed = 'failed';
  static const String verified = 'verified';
  static const String uploaded = 'uploaded';
}
