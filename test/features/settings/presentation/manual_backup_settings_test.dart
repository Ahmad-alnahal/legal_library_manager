// test/features/settings/presentation/manual_backup_settings_test.dart
//
// Widget and BLoC tests for the M11.1 manual-backup panel in SettingsPage.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/managed_copy/application/create_manual_backup.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/manual_backup_result.dart';
import 'package:legal_library_manager/features/managed_copy/presentation/bloc/manual_backup_bloc.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/settings/presentation/pages/settings_page.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

import 'package:legal_library_manager/features/security/application/step_up_manager.dart';

import '../../../support/security_test_doubles.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

const String _defManaged = r'C:\Users\me\Documents\MARJIY\ManagedLibrary';
const String _defBackup = r'C:\Users\me\Documents\MARJIY\DatabaseBackups';
const String _backupButton = 'إنشاء نسخة احتياطية';
const String _backupDialogConfirm = 'إنشاء النسخة';
const String _backupSuccessSnack = 'تم إنشاء النسخة الاحتياطية بنجاح';
const String _backupNotConfiguredSnack = 'لم يتم تهيئة مجلد النسخ الاحتياطي';
const String _backupRootMissingSnack = 'مجلد النسخ الاحتياطي غير متاح';
const String _backupFailedSnack = 'تعذّر إنشاء النسخة الاحتياطية';

/// Fake that returns a scripted result without touching any real infrastructure.
class _FakeCreateManualBackup implements CreateManualBackup {
  _FakeCreateManualBackup(this._result);

  final ManualBackupResult _result;

  @override
  Future<ManualBackupResult> call() async => _result;
}

class _FakeInitializeCopyRoots implements InitializeCopyRoots {
  _FakeInitializeCopyRoots(this.report);
  final CopyRootsSetupReport report;
  @override
  Future<CopyRootsSetupReport> call() async => report;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Registers per-test fakes and pumps the SettingsPage.
///
/// DI base setup (configureDependencies, useStubSessionManager, step-up grant)
/// is done in [setUp] so it runs outside the testWidgets FakeAsync zone.
/// Timers created there are real timers and do not trigger pending-timer errors.
Future<void> _pumpSettings(
  WidgetTester tester, {
  required CopyRootsSetupReport report,
  required ManualBackupResult backupResult,
  Size size = const Size(1280, 800),
}) async {
  if (getIt.isRegistered<InitializeCopyRoots>()) {
    getIt.unregister<InitializeCopyRoots>();
  }
  getIt.registerSingleton<InitializeCopyRoots>(
    _FakeInitializeCopyRoots(report),
  );

  if (getIt.isRegistered<CreateManualBackup>()) {
    getIt.unregister<CreateManualBackup>();
  }
  getIt.registerSingleton<CreateManualBackup>(
    _FakeCreateManualBackup(backupResult),
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

final _anyBackupResult = const ManualBackupSuccess(
  backupPath: r'C:\Backups\x.sqlite',
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AppDatabase>(
      AppDatabase.inMemory(),
      dispose: (db) => db.close(),
    );
    configureDependencies();
    // Settings page hides admin-only controls from operators. Swap in the
    // FakeSessionManager so the admin session is visible without a pending timer.
    useStubSessionManager();
    // Pre-grant step-up so tests that tap admin-only buttons reach the
    // confirmation dialog without interacting with the step-up dialog.
    // Called in setUp (outside testWidgets FakeAsync) so the 5-min timer is
    // a real timer and does not cause pending-fake-timer test failures.
    getIt<StepUpManager>().grant();
  });

  tearDown(() => getIt.reset());

  group('Manual backup panel visibility', () {
    testWidgets('backup button is visible when backup root is configured', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
        backupResult: _anyBackupResult,
      );

      expect(find.text(_backupButton), findsOneWidget);
    });

    testWidgets(
      'backup button is disabled when backup root is not configured',
      (tester) async {
        await _pumpSettings(
          tester,
          report: const CopyRootsSetupReport(
            outcome: CopyRootsSetupOutcome.requiresAttention,
            managedRoot: _defManaged,
            backupRoot: null,
            managedStatus: CopyRootStatus.automatic,
            backupStatus: CopyRootStatus.notConfigured,
          ),
          backupResult: _anyBackupResult,
        );

        // The button is present but not enabled (onPressed is null).
        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text(_backupButton),
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          button.onPressed,
          isNull,
          reason: 'backup button must be disabled when backup root is not set',
        );
      },
    );
  });

  group('Manual backup confirmation dialog', () {
    testWidgets('tapping the backup button shows a confirmation dialog', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
        backupResult: _anyBackupResult,
      );

      await tester.tap(find.text(_backupButton));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('البيانات الوصفية فقط'),
        findsOneWidget,
        reason:
            'dialog must clarify that only metadata is backed up, not source files',
      );
      expect(find.text(_backupDialogConfirm), findsOneWidget);
    });

    testWidgets('cancelling the dialog does not trigger backup', (
      tester,
    ) async {
      final succeeds = const ManualBackupSuccess(
        backupPath: r'C:\Backups\x.sqlite',
      );
      await _pumpSettings(
        tester,
        report: const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
        backupResult: succeeds,
      );

      await tester.tap(find.text(_backupButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      // No snackbar shown — the backup was never triggered.
      expect(find.textContaining(_backupSuccessSnack), findsNothing);
    });
  });

  group('Manual backup snackbar feedback', () {
    testWidgets('success shows Arabic success message', (tester) async {
      await _pumpSettings(
        tester,
        report: const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
        backupResult: const ManualBackupSuccess(
          backupPath: r'C:\Backups\x.sqlite',
        ),
      );

      await tester.tap(find.text(_backupButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_backupDialogConfirm));
      await tester.pumpAndSettle();

      expect(find.textContaining(_backupSuccessSnack), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('not_configured failure shows appropriate Arabic message', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
        backupResult: const ManualBackupFailure(messageKey: 'not_configured'),
      );

      await tester.tap(find.text(_backupButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_backupDialogConfirm));
      await tester.pumpAndSettle();

      expect(find.textContaining(_backupNotConfiguredSnack), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('root_missing failure shows appropriate Arabic message', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
        backupResult: const ManualBackupFailure(messageKey: 'root_missing'),
      );

      await tester.tap(find.text(_backupButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_backupDialogConfirm));
      await tester.pumpAndSettle();

      expect(find.textContaining(_backupRootMissingSnack), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('failed failure shows generic Arabic failure message', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        report: const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
        backupResult: const ManualBackupFailure(messageKey: 'failed'),
      );

      await tester.tap(find.text(_backupButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_backupDialogConfirm));
      await tester.pumpAndSettle();

      expect(find.textContaining(_backupFailedSnack), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('Manual backup BLoC — unit behavior', () {
    test('starts idle (not busy, no message)', () {
      final bloc = ManualBackupBloc(
        _FakeCreateManualBackup(
          const ManualBackupSuccess(backupPath: r'C:\b\x.sqlite'),
        ),
      );
      expect(bloc.state.busy, isFalse);
      expect(bloc.state.messageKey, isNull);
      bloc.close();
    });

    test('emits success messageKey after a successful backup', () async {
      final bloc = ManualBackupBloc(
        _FakeCreateManualBackup(
          const ManualBackupSuccess(backupPath: r'C:\b\x.sqlite'),
        ),
      );

      final states = <ManualBackupState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ManualBackupRequested());
      await bloc.stream.firstWhere((s) => !s.busy);

      await sub.cancel();
      await bloc.close();

      expect(states.last.messageKey, 'success');
      expect(states.last.busy, isFalse);
    });

    test('emits failure messageKey after a backup failure', () async {
      final bloc = ManualBackupBloc(
        _FakeCreateManualBackup(
          const ManualBackupFailure(messageKey: 'failed'),
        ),
      );

      bloc.add(const ManualBackupRequested());
      final finalState = await bloc.stream.firstWhere((s) => !s.busy);
      await bloc.close();

      expect(finalState.messageKey, 'failed');
    });

    test('ignores a second request while busy', () async {
      int callCount = 0;
      final useCase = _CountingCreateManualBackup(
        onCall: () {
          callCount++;
          return const ManualBackupSuccess(backupPath: r'C:\b\x.sqlite');
        },
      );
      final bloc = ManualBackupBloc(useCase);

      bloc.add(const ManualBackupRequested());
      bloc.add(const ManualBackupRequested()); // second should be ignored
      await bloc.stream.firstWhere((s) => !s.busy);
      await bloc.close();

      expect(
        callCount,
        1,
        reason: 'a second request while busy must be dropped',
      );
    });
  });
}

class _CountingCreateManualBackup implements CreateManualBackup {
  _CountingCreateManualBackup({required this.onCall});

  final ManualBackupResult Function() onCall;

  @override
  Future<ManualBackupResult> call() async => onCall();
}
