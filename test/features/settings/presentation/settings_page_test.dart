// test/features/settings/presentation/settings_page_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/repair_copy_root.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/copy_root_picker.dart';
import 'package:legal_library_manager/features/settings/presentation/pages/settings_page.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

import 'package:legal_library_manager/features/security/application/step_up_manager.dart';

import '../../../support/security_test_doubles.dart';

const String _automaticChip = 'مُهيأ تلقائيًا';
const String _customChip = 'موقع مخصص';
const String _missingChip = 'المجلد غير متاح — يتطلب الانتباه';
const String _attentionBanner = 'يتطلب إعداد مواقع النسخ الآمن انتباهك';
const String _recreateButton = 'إعادة إنشاء المجلد';
const String _recreateConfirm = 'إعادة الإنشاء';
const String _recreatedToast = 'تمت إعادة إنشاء المجلد المفقود بأمان';
const String _recreateFailedToast = 'تعذّرت إعادة إنشاء المجلد';

const String _defManaged = r'C:\Users\me\Documents\MARJIY\ManagedLibrary';
const String _defBackup = r'C:\Users\me\Documents\MARJIY\DatabaseBackups';

/// Returns a scripted setup report so the Settings page can be rendered against
/// each per-root status without touching path_provider or the real filesystem.
class _FakeInitializeCopyRoots implements InitializeCopyRoots {
  _FakeInitializeCopyRoots(this.report);
  final CopyRootsSetupReport report;

  @override
  Future<CopyRootsSetupReport> call() async => report;
}

/// Serves a queued sequence of reports, repeating the last one. Lets a repair
/// interaction observe a refreshed (post-repair) state on the second call.
class _SequencedInitializeCopyRoots implements InitializeCopyRoots {
  _SequencedInitializeCopyRoots(this._reports);
  final List<CopyRootsSetupReport> _reports;
  int _index = 0;

  @override
  Future<CopyRootsSetupReport> call() async {
    final report =
        _reports[_index < _reports.length ? _index : _reports.length - 1];
    _index++;
    return report;
  }
}

/// Records picker calls; returns null (simulates user cancelling the OS dialog).
class _FakeCopyRootPicker implements CopyRootPicker {
  int callCount = 0;

  @override
  Future<String?> pick(CopyRootKind kind) async {
    callCount++;
    return null;
  }
}

/// Records the requested kind and returns a scripted repair result.
class _FakeRepairCopyRoot implements RepairCopyRoot {
  _FakeRepairCopyRoot(this.result);
  final RepairCopyRootResult result;
  final List<CopyRootKind> calls = <CopyRootKind>[];

  @override
  Future<RepairCopyRootResult> call(CopyRootKind kind) async {
    calls.add(kind);
    return result;
  }
}

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
    // expected dialog/picker without being intercepted by the step-up dialog.
    getIt<StepUpManager>().grant();
  });

  tearDown(() => getIt.reset());

  testWidgets('shows automatic state for both roots and no attention banner', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.defaultsCreated,
        managedRoot: r'C:\Users\me\Documents\MARJIY\ManagedLibrary',
        backupRoot: r'C:\Users\me\Documents\MARJIY\DatabaseBackups',
        managedStatus: CopyRootStatus.automatic,
        backupStatus: CopyRootStatus.automatic,
      ),
    );

    expect(find.text(_automaticChip), findsNWidgets(2));
    expect(find.textContaining(_attentionBanner), findsNothing);
    expect(
      find.text(r'C:\Users\me\Documents\MARJIY\ManagedLibrary'),
      findsOneWidget,
    );
  });

  testWidgets('shows custom and automatic states distinctly', (tester) async {
    await _pumpSettings(
      tester,
      const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.alreadyConfigured,
        managedRoot: r'D:\Custom\Library',
        backupRoot: r'C:\Users\me\Documents\MARJIY\DatabaseBackups',
        managedStatus: CopyRootStatus.custom,
        backupStatus: CopyRootStatus.automatic,
      ),
    );

    expect(find.text(_customChip), findsOneWidget);
    expect(find.text(_automaticChip), findsOneWidget);
    expect(find.textContaining(_attentionBanner), findsNothing);
  });

  testWidgets('shows missing/attention state with the warning banner', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.requiresAttention,
        managedRoot: r'D:\Custom\Library',
        backupRoot: r'C:\Users\me\Documents\MARJIY\DatabaseBackups',
        managedStatus: CopyRootStatus.missing,
        backupStatus: CopyRootStatus.automatic,
      ),
    );

    expect(find.text(_missingChip), findsOneWidget);
    expect(find.text(_automaticChip), findsOneWidget);
    expect(find.textContaining(_attentionBanner), findsOneWidget);
  });

  testWidgets('shows startup recovery attention without raw paths', (
    tester,
  ) async {
    await getIt<ManagedCopyRepository>().saveStartupRecoveryReport(
      const StartupRecoveryReport(
        status: StartupRecoveryStatus.requiresAttention,
        artifactCount: 2,
      ),
    );

    await _pumpSettings(
      tester,
      const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.alreadyConfigured,
        managedRoot: _defManaged,
        backupRoot: _defBackup,
        managedStatus: CopyRootStatus.automatic,
        backupStatus: CopyRootStatus.automatic,
      ),
    );

    expect(find.textContaining('ملفات عمل غير مكتملة'), findsOneWidget);
    expect(find.textContaining('عدد العناصر: 2'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'ملفات عمل غير مكتملة.*C:\\')),
      findsNothing,
    );
  });

  testWidgets('shows re-create action only beside the missing managed root', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.requiresAttention,
        managedRoot: r'D:\Custom\Library',
        backupRoot: _defBackup,
        managedStatus: CopyRootStatus.missing,
        backupStatus: CopyRootStatus.automatic,
      ),
    );

    // Exactly one re-create action, beside the missing managed root only.
    expect(find.text(_recreateButton), findsOneWidget);
  });

  testWidgets('shows re-create action only beside the missing backup root', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.requiresAttention,
        managedRoot: _defManaged,
        backupRoot: r'E:\Custom\Backups',
        managedStatus: CopyRootStatus.automatic,
        backupStatus: CopyRootStatus.missing,
      ),
    );

    expect(find.text(_recreateButton), findsOneWidget);
  });

  testWidgets('existing folders never show the re-create action', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.alreadyConfigured,
        managedRoot: r'D:\Custom\Library',
        backupRoot: _defBackup,
        managedStatus: CopyRootStatus.custom,
        backupStatus: CopyRootStatus.automatic,
      ),
    );

    expect(find.text(_recreateButton), findsNothing);
  });

  testWidgets(
    'confirmed repair recreates the missing root and refreshes state',
    (tester) async {
      final repair = _FakeRepairCopyRoot(RepairCopyRootResult.repaired);
      final init = _SequencedInitializeCopyRoots(const [
        // Before repair: managed missing, requires attention.
        CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.requiresAttention,
          managedRoot: r'D:\Custom\Library',
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.missing,
          backupStatus: CopyRootStatus.automatic,
        ),
        // After repair: both present, no attention.
        CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: r'D:\Custom\Library',
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.custom,
          backupStatus: CopyRootStatus.automatic,
        ),
      ]);
      await _pumpSettingsWith(tester, init: init, repair: repair);

      expect(find.text(_recreateButton), findsOneWidget);

      await tester.tap(find.text(_recreateButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_recreateConfirm));
      await tester.pumpAndSettle();

      // Exactly the missing managed root was requested.
      expect(repair.calls, [CopyRootKind.managedLibrary]);

      // State refreshed: the action and the missing/attention state are gone.
      expect(find.text(_recreateButton), findsNothing);
      expect(find.text(_missingChip), findsNothing);
      expect(find.textContaining(_attentionBanner), findsNothing);
      expect(find.text(_customChip), findsOneWidget);
      expect(find.textContaining(_recreatedToast), findsOneWidget);

      // Drain the SnackBar auto-dismiss timer so none outlives the test.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'failed repair keeps requires-attention state and shows safe feedback',
    (tester) async {
      final repair = _FakeRepairCopyRoot(RepairCopyRootResult.creationFailed);
      final init = _SequencedInitializeCopyRoots(const [
        CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.requiresAttention,
          managedRoot: r'D:\Custom\Library',
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.missing,
          backupStatus: CopyRootStatus.automatic,
        ),
      ]);
      await _pumpSettingsWith(tester, init: init, repair: repair);

      await tester.tap(find.text(_recreateButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_recreateConfirm));
      await tester.pumpAndSettle();

      expect(repair.calls, [CopyRootKind.managedLibrary]);
      // Requires-attention state is preserved; the action remains available.
      expect(find.text(_missingChip), findsOneWidget);
      expect(find.textContaining(_attentionBanner), findsOneWidget);
      expect(find.text(_recreateButton), findsOneWidget);
      expect(find.textContaining(_recreateFailedToast), findsOneWidget);

      // Drain the SnackBar auto-dismiss timer so none outlives the test.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  // ── M10.2: copy-only policy and safety wording ────────────────────────────

  group('copy-only policy panel', () {
    testWidgets('copy-only policy title and active badge are visible', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
      );

      // settingsCopyPolicyTitle = "سياسة «نسخ فقط»"
      expect(find.textContaining('سياسة «نسخ فقط»'), findsOneWidget);
      // settingsCopyPolicyActive = "سياسة نشطة ومفروضة"
      expect(find.text('سياسة نشطة ومفروضة'), findsOneWidget);
    });

    testWidgets('copy-only policy body explicitly states no mutations', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
      );

      // settingsCopyPolicyBody states: "لا ينقلها ولا يعيد تسميتها ولا يحذفها"
      expect(
        find.textContaining('لا ينقلها ولا يعيد تسميتها ولا يحذفها'),
        findsOneWidget,
      );
    });

    testWidgets('locations panel states changing paths does not move files', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        const CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.alreadyConfigured,
          managedRoot: _defManaged,
          backupRoot: _defBackup,
          managedStatus: CopyRootStatus.automatic,
          backupStatus: CopyRootStatus.automatic,
        ),
      );

      // The locations panel disclaimer: "تغيير المواقع لا ينقل الملفات..."
      expect(find.textContaining('لا ينقل الملفات'), findsWidgets);
    });
  });

  // ── M10.2: location-change confirmation ───────────────────────────────────

  group('location change confirmation', () {
    testWidgets(
      'changing an already-configured root shows a confirmation dialog',
      (tester) async {
        final picker = _FakeCopyRootPicker();
        await _pumpSettings(
          tester,
          const CopyRootsSetupReport(
            outcome: CopyRootsSetupOutcome.alreadyConfigured,
            managedRoot: _defManaged,
            backupRoot: _defBackup,
            managedStatus: CopyRootStatus.automatic,
            backupStatus: CopyRootStatus.automatic,
          ),
          picker: picker,
        );

        // Both roots are set — the button label is "تغيير".
        final changeButtons = find.text('تغيير');
        expect(changeButtons, findsWidgets);

        await tester.tap(changeButtons.first);
        await tester.pumpAndSettle();

        // Confirmation dialog must appear.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('تغيير'), findsWidgets);
        expect(
          find.textContaining('ولا يُنقل أو يُحذف أي ملف موجود'),
          findsOneWidget,
        );

        // Cancel the dialog.
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'cancelling the confirmation dialog does not invoke the folder picker',
      (tester) async {
        final picker = _FakeCopyRootPicker();
        await _pumpSettings(
          tester,
          const CopyRootsSetupReport(
            outcome: CopyRootsSetupOutcome.alreadyConfigured,
            managedRoot: _defManaged,
            backupRoot: _defBackup,
            managedStatus: CopyRootStatus.automatic,
            backupStatus: CopyRootStatus.automatic,
          ),
          picker: picker,
        );

        await tester.tap(find.text('تغيير').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();

        // Dialog dismissed; picker must not have been called.
        expect(picker.callCount, 0);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'first-time setup (no current value) opens picker without a dialog',
      (tester) async {
        final picker = _FakeCopyRootPicker();
        // Only managed root is unconfigured.
        await _pumpSettings(
          tester,
          const CopyRootsSetupReport(
            outcome: CopyRootsSetupOutcome.requiresAttention,
            managedRoot: null,
            backupRoot: _defBackup,
            managedStatus: CopyRootStatus.notConfigured,
            backupStatus: CopyRootStatus.automatic,
          ),
          picker: picker,
        );

        // "اختيار" appears only for the unconfigured root.
        expect(find.text('اختيار'), findsOneWidget);

        await tester.tap(find.text('اختيار'));
        await tester.pumpAndSettle();

        // No dialog — picker called directly.
        expect(find.byType(AlertDialog), findsNothing);
        expect(picker.callCount, 1);
      },
    );
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  CopyRootsSetupReport report, {
  Size size = const Size(1280, 800),
  CopyRootPicker? picker,
}) => _pumpSettingsWith(
  tester,
  init: _FakeInitializeCopyRoots(report),
  picker: picker,
  size: size,
);

Future<void> _pumpSettingsWith(
  WidgetTester tester, {
  required InitializeCopyRoots init,
  RepairCopyRoot? repair,
  CopyRootPicker? picker,
  Size size = const Size(1280, 800),
}) async {
  if (getIt.isRegistered<InitializeCopyRoots>()) {
    getIt.unregister<InitializeCopyRoots>();
  }
  getIt.registerSingleton<InitializeCopyRoots>(init);

  if (repair != null) {
    if (getIt.isRegistered<RepairCopyRoot>()) {
      getIt.unregister<RepairCopyRoot>();
    }
    getIt.registerSingleton<RepairCopyRoot>(repair);
  }

  if (picker != null) {
    if (getIt.isRegistered<CopyRootPicker>()) {
      getIt.unregister<CopyRootPicker>();
    }
    getIt.registerSingleton<CopyRootPicker>(picker);
  }

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
