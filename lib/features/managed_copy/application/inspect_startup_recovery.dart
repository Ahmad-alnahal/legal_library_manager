// lib/features/managed_copy/application/inspect_startup_recovery.dart

import '../domain/entities/startup_recovery_report.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/managed_library_filesystem.dart';

/// Inspects app-owned managed storage at startup for interrupted work.
///
/// This slice only detects and records a safe status. It never deletes, moves,
/// renames, overwrites, modifies, or repairs files.
class InspectStartupRecovery {
  const InspectStartupRecovery({
    required this.repository,
    required this.filesystem,
  });

  final ManagedCopyRepository repository;
  final ManagedLibraryFilesystem filesystem;

  Future<StartupRecoveryReport> call() async {
    final roots = await repository.loadCopyRoots();
    final managedRoot = roots.managedLibraryRoot;
    final backupRoot = roots.backupRoot;
    final artifacts = <String>[];

    if (managedRoot != null && managedRoot.trim().isNotEmpty) {
      final managedArtifacts = await _inspectManagedRoot(managedRoot);
      if (managedArtifacts == null) {
        return _save(
          const StartupRecoveryReport(
            status: StartupRecoveryStatus.inspectionFailed,
          ),
        );
      }
      artifacts.addAll(managedArtifacts);
    }

    if (backupRoot != null && backupRoot.trim().isNotEmpty) {
      final backupArtifacts = await _inspectBackupRoot(backupRoot);
      if (backupArtifacts == null) {
        return _save(
          const StartupRecoveryReport(
            status: StartupRecoveryStatus.inspectionFailed,
          ),
        );
      }
      artifacts.addAll(backupArtifacts);
    }

    if (artifacts.isNotEmpty) {
      return _save(
        StartupRecoveryReport(
          status: StartupRecoveryStatus.requiresAttention,
          artifactCount: artifacts.length,
        ),
      );
    }

    return _save(StartupRecoveryReport.healthy);
  }

  Future<List<String>?> _inspectManagedRoot(String managedRoot) async {
    if (!filesystem.isExistingDirectory(managedRoot)) {
      return null;
    }

    final filesDir = _joinPath(managedRoot, 'files');
    if (!filesystem.isExistingDirectory(filesDir)) {
      return const [];
    }

    final codes = await repository.loadManagedDocumentCodes();
    return filesystem.findStartupRecoveryArtifacts(filesDir, codes);
  }

  Future<List<String>?> _inspectBackupRoot(String backupRoot) async {
    if (!filesystem.isExistingDirectory(backupRoot)) {
      return null;
    }
    return filesystem.findStartupBackupArtifacts(backupRoot);
  }

  Future<StartupRecoveryReport> _save(StartupRecoveryReport report) async {
    await repository.saveStartupRecoveryReport(report);
    return report;
  }

  String _joinPath(String base, String part) {
    final b = base.replaceAll('/', r'\');
    final trimmed = (b.length > 3 && b.endsWith(r'\'))
        ? b.substring(0, b.length - 1)
        : b;
    return '$trimmed\\$part';
  }
}
