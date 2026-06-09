import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:legal_library_manager/app/app.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/shell/presentation/pages/app_shell_page.dart';

// Stable Arabic UI strings asserted by these tests (mirrors lib/l10n/app_ar.arb).
const String _navDashboard = 'لوحة القيادة';
const String _navImport = 'استيراد';
const String _navDocuments = 'المستندات';
const String _navDuplicates = 'إدارة التكرارات';
const String _navSettings = 'الإعدادات';

const String _dashboardTitle = 'ملخص العمليات';
const String _importTitle = 'استيراد ملفات PDF';
const String _settingsTitle = 'إعدادات النظام';
const String _documentsTitle = 'المستندات المؤرشفة';
const String _duplicatesTitle = 'إدارة التكرارات';

const String _copyOnlyPolicy =
    'يقرأ النظام الملفات الأصلية فقط. لا ينقلها ولا يعيد تسميتها ولا يحذفها. '
    'يتم إنشاء نسخة داخل المكتبة المدارة بعد اعتماد التصنيف.';
const String _metricCopiedToLibrary = 'نُسخ إلى المكتبة';

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MarjiyApp());
  await tester.pumpAndSettle();
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

  testWidgets('app defaults to RTL', (tester) async {
    await _pumpShell(tester);

    final BuildContext context = tester.element(find.byType(AppShellPage));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('right-side navigation destinations render', (tester) async {
    await _pumpShell(tester);

    expect(find.text(_navDashboard), findsOneWidget);
    expect(find.text(_navImport), findsOneWidget);
    expect(find.text(_navDocuments), findsOneWidget);
    expect(find.text(_navDuplicates), findsWidgets);
    expect(find.text(_navSettings), findsOneWidget);

    // The navigation sits on the right (start under RTL): its horizontal
    // center is past the middle of the window.
    final double navCenterX = tester.getCenter(find.text(_navSettings)).dx;
    expect(navCenterX, greaterThan(1440 / 2));
  });

  testWidgets('selecting a destination changes the visible page', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Starts on the dashboard.
    expect(find.text(_dashboardTitle), findsOneWidget);
    expect(find.text(_importTitle), findsNothing);

    await tester.tap(find.text(_navImport));
    await tester.pumpAndSettle();
    expect(find.text(_importTitle), findsOneWidget);
    expect(find.text(_dashboardTitle), findsNothing);

    await tester.tap(find.text(_navSettings));
    await tester.pumpAndSettle();
    expect(find.text(_settingsTitle), findsOneWidget);

    await tester.tap(find.text(_navDocuments));
    await tester.pumpAndSettle();
    expect(find.text(_documentsTitle), findsOneWidget);
  });

  testWidgets('shell renders without overflow at supported desktop sizes', (
    tester,
  ) async {
    const List<Size> sizes = [
      Size(1280, 800),
      Size(1440, 900),
      Size(1920, 1080),
    ];

    for (final Size size in sizes) {
      await _pumpShell(tester, size: size);
      expect(tester.takeException(), isNull, reason: 'dashboard @ $size');

      // Visit each section to confirm none overflow at this size.
      for (final String nav in [
        _navImport,
        _navDocuments,
        _navDuplicates,
        _navSettings,
        _navDashboard,
      ]) {
        await tester.tap(find.text(nav).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$nav @ $size');
      }
    }
  });

  testWidgets('copy-only safety wording is visible on relevant screens', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Import screen shows the source-file safety banner.
    await tester.tap(find.text(_navImport));
    await tester.pumpAndSettle();
    expect(find.text(_copyOnlyPolicy), findsOneWidget);

    // Settings screen shows the same copy-only policy.
    await tester.tap(find.text(_navSettings));
    await tester.pumpAndSettle();
    expect(find.text(_copyOnlyPolicy), findsOneWidget);

    // Duplicate review explains metadata-only, protected sources.
    await tester.tap(find.text(_navDuplicates).first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('لا يُحذف أو يُعدّل أو يُنقل أي ملف أصلي'),
      findsOneWidget,
    );
  });

  testWidgets('no source-file move/delete actions appear', (tester) async {
    await _pumpShell(tester);

    // Visit every section and assert no bare move/delete action labels exist.
    for (final String nav in [
      _navImport,
      _navDocuments,
      _navDuplicates,
      _navSettings,
      _navDashboard,
    ]) {
      await tester.tap(find.text(nav).first);
      await tester.pumpAndSettle();

      for (final String forbidden in [
        'حذف',
        'نقل',
        'حذف الملف',
        'نقل الملف',
        'نقل إلى المكتبة',
        'نقل الملفات الأصلية',
      ]) {
        expect(
          find.widgetWithText(FilledButton, forbidden),
          findsNothing,
          reason: 'forbidden FilledButton "$forbidden" on $nav',
        );
        expect(
          find.widgetWithText(OutlinedButton, forbidden),
          findsNothing,
          reason: 'forbidden OutlinedButton "$forbidden" on $nav',
        );
      }
    }

    // The library workflow uses copy wording, never move wording.
    await tester.tap(find.text(_navDashboard).first);
    await tester.pumpAndSettle();
    expect(find.text(_metricCopiedToLibrary), findsOneWidget);
    expect(find.text('النقل للمكتبة'), findsNothing);
  });

  testWidgets('duplicate review title is reachable', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.text(_navDuplicates).first);
    await tester.pumpAndSettle();
    expect(find.text(_duplicatesTitle), findsWidgets);
  });
}
