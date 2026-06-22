// lib/features/managed_copy/application/cleanup_recovery_artifacts.dart

import '../domain/entities/cleanup_recovery_result.dart';
import '../domain/entities/recovery_artifact_summary.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/managed_library_filesystem.dart';
import 'inspect_startup_recovery.dart';

/// Deletes eligible recovery artifacts from app-owned MARJIY roots and
/// refreshes the stored startup inspection report.
///
/// Only `.copying` temp files and incomplete database backup files are deleted.
/// Unregistered final managed PDFs are never touched — they are reported as
/// "manual review required" by [LoadRecoveryReview] and excluded here.
///
/// Every path is validated against its expected root and strict MARJIY filename
/// pattern before deletion is attempted. Any uncertain or malformed path is
/// counted as a failure without deletion.
class CleanupRecoveryArtifacts {
  const CleanupRecoveryArtifacts({
    required this.repository,
    required this.filesystem,
    required this.inspectStartupRecovery,
  });

  final ManagedCopyRepository repository;
  final ManagedLibraryFilesystem filesystem;
  final InspectStartupRecovery inspectStartupRecovery;

  static final _copyingPattern = RegExp(
    r'^DOC-[0-9]{7}\.pdf\.[A-Za-z0-9_-]+\.copying$',
  );
  static final _backupPattern = RegExp(
    r'^legal_library_backup_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}_[A-Za-z0-9_-]+\.sqlite$',
  );

  Future<CleanupRecoveryResult> call(RecoveryArtifactSummary summary) async {
    final roots = await repository.loadCopyRoots();
    final managedRoot = roots.managedLibraryRoot;
    final backupRoot = roots.backupRoot;

    final managedFilesDir =
        (managedRoot != null && managedRoot.trim().isNotEmpty)
        ? _joinPath(managedRoot, 'files')
        : null;

    int cleaned = 0;
    int failed = 0;

    for (final path in summary.copyingFiles) {
      if (managedFilesDir == null ||
          !_isDirectlyInside(path, managedFilesDir) ||
          !_copyingPattern.hasMatch(_lastName(path))) {
        failed++;
        continue;
      }
      final result = await filesystem.deleteRecoveryArtifact(
        path,
        managedFilesDir,
      );
      if (result is FilesystemSuccess) {
        cleaned++;
      } else {
        failed++;
      }
    }

    for (final path in summary.incompleteBackups) {
      if (backupRoot == null ||
          !_isDirectlyInside(path, backupRoot) ||
          !_backupPattern.hasMatch(_lastName(path))) {
        failed++;
        continue;
      }
      final result = await filesystem.deleteRecoveryArtifact(path, backupRoot);
      if (result is FilesystemSuccess) {
        cleaned++;
      } else {
        failed++;
      }
    }

    // Always refresh the inspection report so the settings banner reflects
    // the new state after cleanup.
    await inspectStartupRecovery();

    if (cleaned == 0 && failed == 0) {
      return CleanupRecoveryResult.nothingToClean;
    }
    if (failed == 0) return CleanupRecoveryResult.cleaned;
    if (cleaned == 0) return CleanupRecoveryResult.failed;
    return CleanupRecoveryResult.partialFailure;
  }

  bool _isDirectlyInside(String path, String root) {
    final normPath = path.replaceAll('/', r'\').toLowerCase();
    final normRoot = root.replaceAll('/', r'\').toLowerCase();
    final rootWithSep = normRoot.endsWith(r'\') ? normRoot : '$normRoot\\';
    if (!normPath.startsWith(rootWithSep)) return false;
    final remainder = normPath.substring(rootWithSep.length);
    return remainder.isNotEmpty && !remainder.contains(r'\');
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
