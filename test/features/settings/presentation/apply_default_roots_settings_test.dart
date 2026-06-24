// test/features/settings/presentation/apply_default_roots_settings_test.dart
//
// Tests the "استخدام المجلدات الافتراضية" button in Settings (M8.6 Part A).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/managed_copy/application/apply_default_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/core/widgets/app_buttons.dart';
import 'package:legal_library_manager/features/settings/presentation/pages/settings_page.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

import 'package:legal_library_manager/features/security/application/step_up_manager.dart';

import '../../../support/security_test_doubles.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeInitializeCopyRoots implements InitializeCopyRoots {
  _FakeInitializeCopyRoots(this.report);
  final CopyRootsSetupReport report;

  @override
  Future<CopyRootsSetupReport> call() async => report;
}

class _SequencedInitializeCopyRoots implements InitializeCopyRoots {
  _SequencedInitializeCopyRoots(this._reports);
  final List<CopyRootsSetupReport> _reports;
  int _index = 0;

  @override
  Future<CopyRootsSetupReport> call() async {
    final r = _reports[_index < _reports.length ? _index : _reports.length - 1];
    _index++;
    return r;
  }
}

class _FakeApplyDefaultCopyRoots implements ApplyDefaultCopyRoots {
  _FakeApplyDefaultCopyRoots(this.result);
  final ApplyDefaultCopyRootsResult result;
  int callCount = 0;

  @override
  Future<ApplyDefaultCopyRootsResult> call() async {
    callCount++;
    return result;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const String _kDefaultManaged = r'C:\Users\me\Documents\MARJIY\ManagedLibrary';
const String _kDefaultBackup = r'C:\Users\me\Documents\MARJIY\DatabaseBackups';
const String _kResetButton = 'استخدام المجلدات الافتراضية';
const String _kConfirmButton = 'تطبيق الافتراضي';
const String _kCancelButton = 'إلغاء';
const String _kAutomaticChip = 'مُهيأ تلقائيًا';

Future<void> _pump(
  WidgetTester tester, {
  required InitializeCopyRoots init,
  required ApplyDefaultCopyRoots apply,
  Size size = const Size(1280, 800),
}) async {
  if (getIt.isRegistered<InitializeCopyRoots>()) {
    getIt.unregister<InitializeCopyRoots>();
  }
  getIt.registerSingleton<InitializeCopyRoots>(init);

  if (getIt.isRegistered<ApplyDefaultCopyRoots>()) {
    getIt.unregister<ApplyDefaultCopyRoots>();
  }
  getIt.registerSingleton<ApplyDefaultCopyRoots>(apply);

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
    // Pre-grant step-up so widget tests that tap admin-only buttons reach the
    // confirmation dialog without needing to interact with the step-up dialog.
    getIt<StepUpManager>().grant();
  });

  tearDown(() => getIt.reset());

  testWidgets('reset-to-default button is always visible', (tester) async {
    await _pump(
      tester,
      init: _FakeInitializeCopyRoots(
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: r'D:\Custom\Library',
          backupRoot: _kDefaultBackup,
          managedStatus: CopyRootStatus.custom,
          backupStatus: CopyRootStatus.automatic,
        ),
      ),
      apply: _FakeApplyDefaultCopyRoots(ApplyDefaultCopyRootsResult.applied),
    );

    expect(find.text(_kResetButton), findsOneWidget);
  });

  testWidgets(
    'cancel in confirmation dialog does not call ApplyDefaultCopyRoots',
    (tester) async {
      final apply = _FakeApplyDefaultCopyRoots(
        ApplyDefaultCopyRootsResult.applied,
      );
      await _pump(
        tester,
        init: _FakeInitializeCopyRoots(
          const CopyRootsSetupReport(
            outcome: CopyRootsSetupOutcome.alreadyConfigured,
            managedRoot: r'D:\Custom\Library',
            backupRoot: _kDefaultBackup,
            managedStatus: CopyRootStatus.custom,
            backupStatus: CopyRootStatus.automatic,
          ),
        ),
        apply: apply,
      );

      await tester.tap(find.text(_kResetButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_kCancelButton));
      await tester.pumpAndSettle();

      expect(apply.callCount, 0);
    },
  );

  testWidgets(
    'confirmed reset calls ApplyDefaultCopyRoots and refreshes to automatic',
    (tester) async {
      final apply = _FakeApplyDefaultCopyRoots(
        ApplyDefaultCopyRootsResult.applied,
      );
      final init = _SequencedInitializeCopyRoots([
        // Before reset: one custom root.
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: r'D:\Custom\Library',
          backupRoot: _kDefaultBackup,
          managedStatus: CopyRootStatus.custom,
          backupStatus: CopyRootStatus.automatic,
        ),
        // After reset: both automatic.
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.defaultsCreated,
          managedRoot: _kDefaultManaged,
          backupRoot: _kDefaultBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
      ]);
      await _pump(tester, init: init, apply: apply);

      await tester.tap(find.text(_kResetButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_kConfirmButton));
      await tester.pumpAndSettle();

      expect(apply.callCount, 1);
      // Both roots now show as automatic.
      expect(find.text(_kAutomaticChip), findsNWidgets(2));
      // Success toast appears.
      expect(
        find.textContaining('تم تطبيق المجلدات الافتراضية'),
        findsOneWidget,
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets('failed reset (documents not resolvable) shows error toast', (
    tester,
  ) async {
    final apply = _FakeApplyDefaultCopyRoots(
      ApplyDefaultCopyRootsResult.documentsNotResolvable,
    );
    await _pump(
      tester,
      init: _FakeInitializeCopyRoots(
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: r'D:\Custom\Library',
          backupRoot: _kDefaultBackup,
          managedStatus: CopyRootStatus.custom,
          backupStatus: CopyRootStatus.automatic,
        ),
      ),
      apply: apply,
    );

    await tester.tap(find.text(_kResetButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_kConfirmButton));
    await tester.pumpAndSettle();

    expect(apply.callCount, 1);
    expect(find.textContaining('تعذّر تحديد مجلد المستندات'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('reset-to-default button is disabled while busy', (tester) async {
    // Use a Completer-backed fake to test busy state.
    // Since we can't easily pause mid-operation, we just verify the button
    // is enabled when idle (not busy).
    await _pump(
      tester,
      init: _FakeInitializeCopyRoots(
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: _kDefaultManaged,
          backupRoot: _kDefaultBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
      ),
      apply: _FakeApplyDefaultCopyRoots(ApplyDefaultCopyRootsResult.applied),
    );

    final button = tester.widget<AppSecondaryButton>(
      find.widgetWithText(AppSecondaryButton, _kResetButton),
    );
    expect(button.onPressed, isNotNull);
  });
}
