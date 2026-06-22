// test/features/settings/presentation/recovery_review_settings_test.dart
//
// Widget tests for M11.3 recovery review integration in SettingsPage.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/managed_copy/application/cleanup_recovery_artifacts.dart';
import 'package:legal_library_manager/features/managed_copy/application/inspect_startup_recovery.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/load_recovery_review.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/cleanup_recovery_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/document_copy_state.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_persistence_data.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_file_ref.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/recovery_artifact_summary.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/source_file_candidate.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/settings/presentation/pages/settings_page.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

// ── String constants (Arabic l10n) ────────────────────────────────────────────

const _reviewButton = 'مراجعة';
const _reviewDialogTitle = 'مراجعة ملفات الاسترداد';
const _cleanupButton = 'حذف الملفات المؤهلة';
const _confirmAction = 'حذف الآن';
const _cancelButton = 'إلغاء';
const _snackCleaned = 'تم حذف الملفات المؤهلة بنجاح';

// ── Fake infrastructure ───────────────────────────────────────────────────────

class _FakeRepo implements ManagedCopyRepository {
  _FakeRepo({
    required this.roots,
    this.recoveryReport = StartupRecoveryReport.healthy,
  });

  final CopyRoots roots;
  final StartupRecoveryReport recoveryReport;

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      recoveryReport;

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {}

  @override
  Future<List<String>> loadManagedDocumentCodes() async => const [];

  @override
  Future<String> loadDatabaseRoot() async => r'C:\AppData';

  @override
  Future<void> appendFileEvent({
    required int? documentId,
    required int? fileId,
    required String eventTypeKey,
    required String operationId,
    required String resultKey,
    String? sourcePath,
    String? destinationPath,
    String? expectedSha256,
    String? actualSha256,
    String? errorCode,
    String? messageSafe,
  }) async {}

  @override
  Future<DocumentCopyState?> loadDocumentState(int documentId) async => null;

  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) async {}

  @override
  Future<List<String>> loadDocumentSourcePaths(int documentId) async => [];

  @override
  Future<List<String>> loadAllSourcePaths() async => [];

  @override
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId) async =>
      [];

  @override
  Future<String> allocateDocumentCode(int documentId) async => 'DOC-0000001';

  @override
  Future<int> persistManagedCopySuccess(
    ManagedCopyPersistenceData data,
  ) async => 0;

  @override
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId) async => [];

  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}

  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}

  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) async {}
}

class _FakeFilesystem implements ManagedLibraryFilesystem {
  _FakeFilesystem({this.summary = const RecoveryArtifactSummary()});

  final RecoveryArtifactSummary summary;
  final deletedPaths = <String>[];

  @override
  bool isExistingDirectory(String path) => true;

  @override
  bool isExistingFile(String path) => false;

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async => [...summary.copyingFiles, ...summary.unregisteredFinalPdfs];

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async =>
      summary.incompleteBackups;

  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
    String path,
    String allowedRoot,
  ) async {
    deletedPaths.add(path);
    return const FilesystemSuccess();
  }

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(String path) async =>
      const FilesystemSuccess();

  @override
  Future<FilesystemOperationResult> copyFile(String src, String dst) async =>
      const FilesystemSuccess();

  @override
  Future<FilesystemOperationResult> finalizeFile(
    String tmp,
    String fin,
  ) async => const FilesystemSuccess();

  @override
  Future<int?> fileSize(String path) async => null;

  @override
  Future<List<String>?> findRecoveryArtifacts(String dir, String code) async =>
      [];

  @override
  Future<FilesystemOperationResult> deleteFile(String path) async =>
      const FilesystemSuccess();
}

class _FakeInitializeCopyRoots implements InitializeCopyRoots {
  _FakeInitializeCopyRoots(this.report);
  final CopyRootsSetupReport report;
  @override
  Future<CopyRootsSetupReport> call() async => report;
}

/// Scripted [LoadRecoveryReview] that returns a fixed summary.
class _FakeLoadRecoveryReview extends LoadRecoveryReview {
  _FakeLoadRecoveryReview(this._summary, _FakeRepo repo, _FakeFilesystem fs)
    : super(repository: repo, filesystem: fs);

  final RecoveryArtifactSummary? _summary;

  @override
  Future<RecoveryArtifactSummary?> call() async => _summary;
}

/// Scripted [CleanupRecoveryArtifacts] that returns a fixed result.
class _FakeCleanupRecoveryArtifacts extends CleanupRecoveryArtifacts {
  _FakeCleanupRecoveryArtifacts(
    this._result,
    _FakeRepo repo,
    _FakeFilesystem fs,
  ) : super(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: _FakeInspect(repo, fs),
      );

  final CleanupRecoveryResult _result;

  @override
  Future<CleanupRecoveryResult> call(RecoveryArtifactSummary summary) async =>
      _result;
}

class _FakeInspect extends InspectStartupRecovery {
  _FakeInspect(_FakeRepo repo, _FakeFilesystem fs)
    : super(repository: repo, filesystem: fs);

  @override
  Future<StartupRecoveryReport> call() async => StartupRecoveryReport.healthy;
}

// ── Pump helper ───────────────────────────────────────────────────────────────

Future<void> _pumpSettings(
  WidgetTester tester, {
  required CopyRootsSetupReport report,
  required StartupRecoveryReport recoveryReport,
  required RecoveryArtifactSummary reviewSummary,
  CleanupRecoveryResult cleanupResult = CleanupRecoveryResult.cleaned,
  Size size = const Size(1280, 800),
}) async {
  await getIt.reset();
  getIt.registerSingleton<AppDatabase>(
    AppDatabase.inMemory(),
    dispose: (db) => db.close(),
  );
  configureDependencies();

  final fakeRepo = _FakeRepo(
    roots: report.toRoots(),
    recoveryReport: recoveryReport,
  );
  final fakeFs = _FakeFilesystem(summary: reviewSummary);

  if (getIt.isRegistered<InitializeCopyRoots>()) {
    getIt.unregister<InitializeCopyRoots>();
  }
  getIt.registerSingleton<InitializeCopyRoots>(
    _FakeInitializeCopyRoots(report),
  );

  if (getIt.isRegistered<LoadRecoveryReview>()) {
    getIt.unregister<LoadRecoveryReview>();
  }
  getIt.registerSingleton<LoadRecoveryReview>(
    _FakeLoadRecoveryReview(reviewSummary, fakeRepo, fakeFs),
  );

  if (getIt.isRegistered<CleanupRecoveryArtifacts>()) {
    getIt.unregister<CleanupRecoveryArtifacts>();
  }
  getIt.registerSingleton<CleanupRecoveryArtifacts>(
    _FakeCleanupRecoveryArtifacts(cleanupResult, fakeRepo, fakeFs),
  );

  // Persist the scripted recovery report to the in-memory DB so
  // CopySettingsBloc.loadStartupRecoveryReport() returns the expected status.
  await getIt<ManagedCopyRepository>().saveStartupRecoveryReport(
    recoveryReport,
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    const MaterialApp(
      locale: Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SettingsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

extension on CopyRootsSetupReport {
  CopyRoots toRoots() =>
      CopyRoots(managedLibraryRoot: managedRoot, backupRoot: backupRoot);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) await getIt.reset();
  });

  const defaultReport = CopyRootsSetupReport(
    outcome: CopyRootsSetupOutcome.defaultsCreated,
    managedRoot: r'C:\MARJIY\ManagedLibrary',
    backupRoot: r'C:\MARJIY\DatabaseBackups',
    managedStatus: CopyRootStatus.automatic,
    backupStatus: CopyRootStatus.automatic,
  );

  group('Recovery review banner action', () {
    testWidgets(
      'review button appears in banner when recovery requires attention',
      (tester) async {
        await _pumpSettings(
          tester,
          report: defaultReport,
          recoveryReport: const StartupRecoveryReport(
            status: StartupRecoveryStatus.requiresAttention,
            artifactCount: 2,
          ),
          reviewSummary: const RecoveryArtifactSummary(
            copyingFiles: [
              r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
            ],
            incompleteBackups: [
              r'C:\MARJIY\DatabaseBackups\legal_library_backup_2026-06-21_120000_manual.sqlite',
            ],
          ),
        );

        expect(
          find.text(_reviewButton),
          findsOneWidget,
          reason: 'Review action must appear in the startup recovery banner',
        );
      },
    );

    testWidgets('review button does not appear when recovery is healthy', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: defaultReport,
        recoveryReport: StartupRecoveryReport.healthy,
        reviewSummary: const RecoveryArtifactSummary(),
      );

      expect(find.text(_reviewButton), findsNothing);
    });
  });

  group('Recovery review dialog', () {
    testWidgets('tapping review opens the review dialog', (tester) async {
      await _pumpSettings(
        tester,
        report: defaultReport,
        recoveryReport: const StartupRecoveryReport(
          status: StartupRecoveryStatus.requiresAttention,
          artifactCount: 1,
        ),
        reviewSummary: const RecoveryArtifactSummary(
          copyingFiles: [
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
          ],
        ),
      );

      await tester.tap(find.text(_reviewButton));
      await tester.pumpAndSettle();

      expect(
        find.text(_reviewDialogTitle),
        findsOneWidget,
        reason: 'Review dialog must appear after tapping the review button',
      );
    });

    testWidgets('dialog shows counts without raw file paths', (tester) async {
      await _pumpSettings(
        tester,
        report: defaultReport,
        recoveryReport: const StartupRecoveryReport(
          status: StartupRecoveryStatus.requiresAttention,
          artifactCount: 3,
        ),
        reviewSummary: const RecoveryArtifactSummary(
          copyingFiles: [
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf.copy_y.copying',
          ],
          unregisteredFinalPdfs: [
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000003.pdf',
          ],
        ),
      );

      await tester.tap(find.text(_reviewButton));
      await tester.pumpAndSettle();

      // Dialog must be open.
      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);

      // Raw filesystem paths from the review summary must not appear anywhere
      // inside the AlertDialog's subtree.
      final rawPaths = [
        r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
        r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf.copy_y.copying',
        r'C:\MARJIY\ManagedLibrary\files\DOC-0000003.pdf',
      ];
      for (final rawPath in rawPaths) {
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.textContaining(rawPath),
          ),
          findsNothing,
          reason: 'Dialog must not expose raw path: $rawPath',
        );
      }

      // Dialog should show count-based text (e.g. "2" for two copying files).
      expect(
        find.descendant(of: dialogFinder, matching: find.textContaining('2')),
        findsWidgets,
        reason: 'Dialog should show artifact counts',
      );
    });

    testWidgets(
      'cleanup button appears only when there are eligible artifacts',
      (tester) async {
        await _pumpSettings(
          tester,
          report: defaultReport,
          recoveryReport: const StartupRecoveryReport(
            status: StartupRecoveryStatus.requiresAttention,
            artifactCount: 1,
          ),
          reviewSummary: const RecoveryArtifactSummary(
            copyingFiles: [
              r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
            ],
          ),
        );

        await tester.tap(find.text(_reviewButton));
        await tester.pumpAndSettle();

        expect(find.text(_cleanupButton), findsOneWidget);
      },
    );

    testWidgets(
      'cleanup button is absent when only unregistered PDFs present',
      (tester) async {
        await _pumpSettings(
          tester,
          report: defaultReport,
          recoveryReport: const StartupRecoveryReport(
            status: StartupRecoveryStatus.requiresAttention,
            artifactCount: 1,
          ),
          reviewSummary: const RecoveryArtifactSummary(
            unregisteredFinalPdfs: [
              r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf',
            ],
          ),
        );

        await tester.tap(find.text(_reviewButton));
        await tester.pumpAndSettle();

        expect(
          find.text(_cleanupButton),
          findsNothing,
          reason: 'Cleanup button must be absent when no eligible artifacts',
        );
      },
    );

    testWidgets('tapping cleanup shows confirmation dialog', (tester) async {
      await _pumpSettings(
        tester,
        report: defaultReport,
        recoveryReport: const StartupRecoveryReport(
          status: StartupRecoveryStatus.requiresAttention,
          artifactCount: 1,
        ),
        reviewSummary: const RecoveryArtifactSummary(
          copyingFiles: [
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
          ],
        ),
      );

      await tester.tap(find.text(_reviewButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_cleanupButton));
      await tester.pumpAndSettle();

      expect(
        find.text(_confirmAction),
        findsOneWidget,
        reason: 'Cleanup must require explicit user confirmation',
      );
    });

    testWidgets('cancelling cleanup confirmation does not proceed', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: defaultReport,
        recoveryReport: const StartupRecoveryReport(
          status: StartupRecoveryStatus.requiresAttention,
          artifactCount: 1,
        ),
        reviewSummary: const RecoveryArtifactSummary(
          copyingFiles: [
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
          ],
        ),
      );

      await tester.tap(find.text(_reviewButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_cleanupButton));
      await tester.pumpAndSettle();

      // Cancel the confirmation dialog
      await tester.tap(find.text(_cancelButton).last);
      await tester.pumpAndSettle();

      // Review dialog still open; no snack
      expect(find.text(_reviewDialogTitle), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('confirming cleanup closes dialog and shows success snack', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: defaultReport,
        recoveryReport: const StartupRecoveryReport(
          status: StartupRecoveryStatus.requiresAttention,
          artifactCount: 1,
        ),
        reviewSummary: const RecoveryArtifactSummary(
          copyingFiles: [
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_x.copying',
          ],
        ),
        cleanupResult: CleanupRecoveryResult.cleaned,
      );

      await tester.tap(find.text(_reviewButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_cleanupButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_confirmAction));
      await tester.pumpAndSettle();

      expect(
        find.text(_reviewDialogTitle),
        findsNothing,
        reason: 'Review dialog must close after successful cleanup',
      );
      expect(
        find.textContaining(_snackCleaned),
        findsOneWidget,
        reason: 'Success snackbar must appear after successful cleanup',
      );
    });
  });
}
