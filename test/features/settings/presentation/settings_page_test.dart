// test/features/settings/presentation/settings_page_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/repair_copy_root.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/copy_root_picker.dart';
import 'package:legal_library_manager/features/settings/presentation/pages/settings_page.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

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
}

Future<void> _pumpSettings(
  WidgetTester tester,
  CopyRootsSetupReport report, {
  Size size = const Size(1280, 800),
}) => _pumpSettingsWith(
  tester,
  init: _FakeInitializeCopyRoots(report),
  size: size,
);

Future<void> _pumpSettingsWith(
  WidgetTester tester, {
  required InitializeCopyRoots init,
  RepairCopyRoot? repair,
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
