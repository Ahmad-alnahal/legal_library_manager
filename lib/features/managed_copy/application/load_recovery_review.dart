// lib/features/managed_copy/application/load_recovery_review.dart

import '../domain/entities/recovery_artifact_summary.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/managed_library_filesystem.dart';

/// Loads a typed [RecoveryArtifactSummary] by re-running the startup artifact
/// scan and categorizing results by cleanup eligibility.
///
/// Returns null when any root directory cannot be inspected safely. This use
/// case is read-only: it never modifies, deletes, or moves any file.
class LoadRecoveryReview {
  const LoadRecoveryReview({
    required this.repository,
    required this.filesystem,
  });

  final ManagedCopyRepository repository;
  final ManagedLibraryFilesystem filesystem;

  static final _copyingPattern = RegExp(
    r'^DOC-[0-9]{7}\.pdf\.[A-Za-z0-9_-]+\.copying$',
  );
  static final _finalPdfPattern = RegExp(r'^DOC-[0-9]{7}\.pdf$');

  Future<RecoveryArtifactSummary?> call() async {
    final roots = await repository.loadCopyRoots();
    final copyingFiles = <String>[];
    final unregisteredFinalPdfs = <String>[];
    final incompleteBackups = <String>[];

    final managedRoot = roots.managedLibraryRoot;
    if (managedRoot != null && managedRoot.trim().isNotEmpty) {
      final filesDir = _joinPath(managedRoot, 'files');
      if (filesystem.isExistingDirectory(filesDir)) {
        final codes = await repository.loadManagedDocumentCodes();
        final artifacts = await filesystem.findStartupRecoveryArtifacts(
          filesDir,
          codes,
        );
        if (artifacts == null) return null;
        for (final path in artifacts) {
          final name = _lastName(path);
          if (_copyingPattern.hasMatch(name)) {
            copyingFiles.add(path);
          } else if (_finalPdfPattern.hasMatch(name)) {
            unregisteredFinalPdfs.add(path);
          }
        }
      }
    }

    final backupRoot = roots.backupRoot;
    if (backupRoot != null && backupRoot.trim().isNotEmpty) {
      if (filesystem.isExistingDirectory(backupRoot)) {
        final artifacts = await filesystem.findStartupBackupArtifacts(
          backupRoot,
        );
        if (artifacts == null) return null;
        incompleteBackups.addAll(artifacts);
      }
    }

    return RecoveryArtifactSummary(
      copyingFiles: copyingFiles,
      unregisteredFinalPdfs: unregisteredFinalPdfs,
      incompleteBackups: incompleteBackups,
    );
  }

  String _joinPath(String base, String part) {
    final b = base.replaceAll('/', r'\');
    final trimmed = (b.length > 3 && b.endsWith(r'\'))
        ? b.substring(0, b.length - 1)
        : b;
    return '$trimmed\\$part';
  }

  String _lastName(String path) {
    final normalized = path.replaceAll('/', r'\');
    final idx = normalized.lastIndexOf(r'\');
    return idx < 0 ? normalized : normalized.substring(idx + 1);
  }
}
