// lib/features/managed_copy/domain/entities/copy_roots.dart

/// The two storage roots required for a managed-copy operation.
class CopyRoots {
  const CopyRoots({this.managedLibraryRoot, this.backupRoot});

  /// Path to the MARJIY managed-library root, or null if not yet configured.
  final String? managedLibraryRoot;

  /// Path to the database-backup folder, or null if not yet configured.
  final String? backupRoot;

  bool get areBothConfigured =>
      managedLibraryRoot != null && backupRoot != null;
}
