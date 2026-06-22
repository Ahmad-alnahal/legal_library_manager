// test/features/managed_copy/presentation/bloc/recovery_review_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/cleanup_recovery_artifacts.dart';
import 'package:legal_library_manager/features/managed_copy/application/inspect_startup_recovery.dart';
import 'package:legal_library_manager/features/managed_copy/application/load_recovery_review.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/recovery_artifact_summary.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/presentation/bloc/recovery_review_bloc.dart';

void main() {
  const managedRoot = r'C:\MARJIY\ManagedLibrary';
  const filesDir = r'C:\MARJIY\ManagedLibrary\files';

  group('RecoveryReviewBloc', () {
    test('initial state has loading=false and no summary', () {
      final bloc = _buildBloc(_FakeRepo(roots: const CopyRoots()), _FakeFs());
      expect(bloc.state.loading, isFalse);
      expect(bloc.state.summary, isNull);
      expect(bloc.state.cleanupMessageKey, isNull);
      bloc.close();
    });

    test('RecoveryReviewStarted emits loading then loaded state', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFs()..existingDirs.addAll({managedRoot, filesDir});
      final bloc = _buildBloc(repo, fs);

      final states = <RecoveryReviewState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const RecoveryReviewStarted());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.first.loading, isTrue);
      expect(states.last.loading, isFalse);
      bloc.close();
    });

    test('summary is populated after load with copying artifact', () async {
      const copyingPath =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying';
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFs()
        ..existingDirs.addAll({managedRoot, filesDir})
        ..managedArtifacts = const [copyingPath];
      final bloc = _buildBloc(repo, fs);

      bloc.add(const RecoveryReviewStarted());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.loading, isFalse);
      expect(bloc.state.summary?.copyingFiles, contains(copyingPath));
      bloc.close();
    });

    test(
      'RecoveryReviewCleanupConfirmed does nothing when no summary',
      () async {
        final bloc = _buildBloc(_FakeRepo(roots: const CopyRoots()), _FakeFs());

        final states = <RecoveryReviewState>[];
        final sub = bloc.stream.listen(states.add);
        bloc.add(const RecoveryReviewCleanupConfirmed());
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(states, isEmpty);
        bloc.close();
      },
    );

    test(
      'cleanup emits cleaningUp then result with cleanupMessageKey',
      () async {
        const path =
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying';
        final repo = _FakeRepo(
          roots: const CopyRoots(managedLibraryRoot: managedRoot),
        );
        final fs = _FakeFs()..deletionResults[path] = const FilesystemSuccess();
        final bloc = _buildBloc(repo, fs);

        bloc.emit(
          RecoveryReviewState(
            loading: false,
            summary: const RecoveryArtifactSummary(copyingFiles: [path]),
          ),
        );

        final states = <RecoveryReviewState>[];
        final sub = bloc.stream.listen(states.add);
        bloc.add(const RecoveryReviewCleanupConfirmed());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(states.any((s) => s.cleaningUp), isTrue);
        expect(states.last.cleanupMessageKey, isNotNull);
        bloc.close();
      },
    );

    test('cleanup emits cleaned message key when deletion succeeds', () async {
      const path =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying';
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFs()..deletionResults[path] = const FilesystemSuccess();
      final bloc = _buildBloc(repo, fs);

      bloc.emit(
        RecoveryReviewState(
          loading: false,
          summary: const RecoveryArtifactSummary(copyingFiles: [path]),
        ),
      );

      final states = <RecoveryReviewState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const RecoveryReviewCleanupConfirmed());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.last.cleanupMessageKey, 'cleaned');
      bloc.close();
    });

    test('cleanup increments sequence on result', () async {
      final repo = _FakeRepo(roots: const CopyRoots());
      final bloc = _buildBloc(repo, _FakeFs());

      bloc.emit(
        const RecoveryReviewState(
          loading: false,
          summary: RecoveryArtifactSummary(),
        ),
      );

      final initialSeq = bloc.state.sequence;
      final states = <RecoveryReviewState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const RecoveryReviewCleanupConfirmed());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.last.sequence, greaterThan(initialSeq));
      bloc.close();
    });
  });
}

// ── Builders ──────────────────────────────────────────────────────────────────

RecoveryReviewBloc _buildBloc(_FakeRepo repo, _FakeFs fs) {
  final inspect = _FakeInspect(repo, fs);
  return RecoveryReviewBloc(
    LoadRecoveryReview(repository: repo, filesystem: fs),
    CleanupRecoveryArtifacts(
      repository: repo,
      filesystem: fs,
      inspectStartupRecovery: inspect,
    ),
  );
}

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeRepo extends ManagedCopyRepository {
  _FakeRepo({required this.roots});

  final CopyRoots roots;

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

  @override
  Future<List<String>> loadManagedDocumentCodes() async => const [];

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFs extends ManagedLibraryFilesystem {
  final existingDirs = <String>{};
  final deletedPaths = <String>[];
  final deletionResults = <String, FilesystemOperationResult>{};
  List<String>? managedArtifacts = const [];
  List<String>? backupArtifacts = const [];

  @override
  bool isExistingDirectory(String path) => existingDirs.contains(path);

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async => managedArtifacts;

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async =>
      backupArtifacts;

  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
    String path,
    String allowedRoot,
  ) async {
    final result = deletionResults[path] ?? const FilesystemSuccess();
    if (result is FilesystemSuccess) deletedPaths.add(path);
    return result;
  }

  @override
  bool isExistingFile(String path) => false;

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(String path) =>
      throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> copyFile(String src, String dst) =>
      throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> finalizeFile(String tmp, String fin) =>
      throw UnimplementedError();

  @override
  Future<int?> fileSize(String path) => throw UnimplementedError();

  @override
  Future<List<String>?> findRecoveryArtifacts(String dir, String code) =>
      throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> deleteFile(String path) =>
      throw UnimplementedError();
}

class _FakeInspect extends InspectStartupRecovery {
  _FakeInspect(_FakeRepo repo, _FakeFs fs)
    : super(repository: repo, filesystem: fs);

  @override
  Future<StartupRecoveryReport> call() async => StartupRecoveryReport.healthy;
}
