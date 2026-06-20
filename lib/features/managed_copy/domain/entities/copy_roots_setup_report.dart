// lib/features/managed_copy/domain/entities/copy_roots_setup_report.dart

/// How a single copy root is currently configured.
enum CopyRootStatus {
  /// No value is stored in settings for this root.
  notConfigured,

  /// Configured at the MARJIY default location and the directory exists.
  automatic,

  /// Configured at a user-chosen location and the directory exists.
  custom,

  /// Configured but the directory is missing or inaccessible. Requires user
  /// attention; custom locations are never recreated automatically.
  missing,
}

/// What automatic copy-root initialization did (or could not do).
enum CopyRootsSetupOutcome {
  /// Both roots were already configured and their directories exist.
  alreadyConfigured,

  /// Neither root was configured; both defaults were created and persisted.
  defaultsCreated,

  /// Exactly one root was configured; only the missing root was filled with
  /// its default. The existing root was not changed.
  missingRootFilled,

  /// A previously configured default MARJIY directory was missing and has
  /// been safely recreated. Persisted settings were not changed.
  defaultRecreated,

  /// Configuration could not be completed safely. Managed-copy actions stay
  /// blocked until the user resolves it from Settings.
  requiresAttention,
}

/// Stable, typed result of automatic copy-root initialization.
///
/// Carries the currently persisted root paths (when known) and a per-root
/// status for Settings display. Never contains raw OS exception details.
class CopyRootsSetupReport {
  const CopyRootsSetupReport({
    required this.outcome,
    this.managedRoot,
    this.backupRoot,
    this.managedStatus = CopyRootStatus.notConfigured,
    this.backupStatus = CopyRootStatus.notConfigured,
  });

  final CopyRootsSetupOutcome outcome;

  /// Persisted managed-library root, or null when not configured.
  final String? managedRoot;

  /// Persisted database-backup root, or null when not configured.
  final String? backupRoot;

  final CopyRootStatus managedStatus;
  final CopyRootStatus backupStatus;

  bool get requiresAttention =>
      outcome == CopyRootsSetupOutcome.requiresAttention;
}
