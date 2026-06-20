import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/app/app.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/settings/presentation/pages/settings_page.dart';
import 'package:legal_library_manager/features/shell/presentation/widgets/side_navigation.dart';

import '../../support/managed_copy_test_doubles.dart';

// NOTE: These are Flutter *layout* regression tests. They do NOT (and cannot)
// verify the native Windows minimum-window-size enforcement, which lives in the
// Win32 runner (windows/runner/win32_window.cpp, WM_GETMINMAXINFO). They only
// prove the Flutter shell degrades gracefully when it transiently receives
// constraints below the supported minimum (live resize, DPI changes, startup).

const List<IconData> _navIcons = [
  Icons.space_dashboard_outlined, // dashboard
  Icons.download_outlined, // import
  Icons.description_outlined, // documents
  Icons.fact_check_outlined, // review and classification
  Icons.account_tree_outlined, // category management
  Icons.difference_outlined, // duplicate review
  Icons.settings_outlined, // settings
];

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  await _setSize(tester, size);
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
    // Settings (visited below) triggers automatic copy-root setup, whose
    // production resolver calls path_provider — a platform channel that never
    // completes under flutter_test. The stub keeps it in-process.
    useStubDocumentsDirectoryResolver();
  });

  // Supported minimum plus deliberately tiny transient constraints.
  const List<Size> sizes = [
    Size(640, 600), // supported minimum
    Size(640, 300), // very short
    Size(300, 200), // tiny transient (below supported minimum)
  ];

  for (final Size size in sizes) {
    testWidgets('shell renders without exceptions at $size', (tester) async {
      await _pumpAt(tester, size);
      expect(tester.takeException(), isNull, reason: 'initial @ $size');
      // The navigation rail is present at every size.
      expect(find.byType(SideNavigation), findsOneWidget);

      // Every destination remains reachable (scrolling the rail if needed) and
      // tappable without throwing.
      for (final IconData icon in _navIcons) {
        final Finder navIcon = find.descendant(
          of: find.byType(SideNavigation),
          matching: find.byIcon(icon),
        );
        expect(navIcon, findsOneWidget, reason: '$icon present @ $size');
        await tester.ensureVisible(navIcon);
        await tester.pumpAndSettle();
        await tester.tap(navIcon);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'tap $icon @ $size');
      }
    });
  }

  testWidgets('every destination is reachable via scrolling when tiny', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(300, 200));
    // Settings is the last rail item and is off-screen at this height; it must
    // still be reachable by scrolling the rail.
    final Finder settingsIcon = find.descendant(
      of: find.byType(SideNavigation),
      matching: find.byIcon(Icons.settings_outlined),
    );
    // The rail is a lazily-built scrollable list; scroll until Settings (the
    // last destination) is built and visible before tapping it.
    await tester.scrollUntilVisible(
      settingsIcon,
      120,
      scrollable: find.descendant(
        of: find.byType(SideNavigation),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(settingsIcon);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('resize normal -> tiny -> minimum -> normal never throws', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1280, 800));
    expect(tester.takeException(), isNull, reason: 'normal');

    await _setSize(tester, const Size(300, 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'tiny transient');

    await _setSize(tester, const Size(640, 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'supported minimum');

    await _setSize(tester, const Size(1280, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'back to normal');

    // Shell still functional: navigation rail present.
    expect(find.byType(SideNavigation), findsOneWidget);
  });
}
