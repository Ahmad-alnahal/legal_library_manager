import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/app/app.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/dashboard/presentation/widgets/metric_card.dart';
import 'package:legal_library_manager/features/shell/presentation/widgets/side_navigation.dart';

import '../../support/managed_copy_test_doubles.dart';

// Navigation destination icons (unique within the rail). Tapping by icon works
// whether the rail is extended (with labels) or collapsed to icons only, which
// is what happens at the narrow widths exercised here.
const List<IconData> _navIcons = [
  Icons.space_dashboard_outlined, // dashboard
  Icons.download_outlined, // import
  Icons.description_outlined, // documents
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

Future<void> _tapNav(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(SideNavigation),
      matching: find.byIcon(icon),
    ),
  );
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

  // Realistic narrow Windows client areas, plus the previously-tested width.
  const List<Size> sizes = [
    Size(1280, 800),
    Size(1024, 700),
    Size(800, 600),
    Size(640, 600),
  ];

  for (final Size size in sizes) {
    testWidgets('no overflow on any page at $size', (tester) async {
      await _pumpAt(tester, size);

      // Dashboard renders without overflow and still shows its metric cards
      // backed by real (empty) database data — all counts are '0'.
      expect(tester.takeException(), isNull, reason: 'dashboard @ $size');
      expect(find.byType(MetricCard), findsWidgets, reason: 'metrics @ $size');

      // Visit every destination; nothing may overflow at this size.
      for (final IconData icon in _navIcons) {
        await _tapNav(tester, icon);
        expect(tester.takeException(), isNull, reason: '$icon @ $size');
      }
    });
  }

  testWidgets('metric cards remain readable and stable when narrow', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(640, 600));
    // Cards have real, non-degenerate dimensions (no zero/negative widths).
    for (final Element e in find.byType(MetricCard).evaluate()) {
      final Size cardSize = e.size!;
      expect(cardSize.width, greaterThan(120), reason: 'card too narrow');
      expect(cardSize.height, greaterThan(0));
    }
    // With a real empty database, total imported files = 0.
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('resizing the dashboard wide -> narrow -> wide never overflows', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1440, 900));
    expect(tester.takeException(), isNull, reason: 'initial wide');

    await _setSize(tester, const Size(640, 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after shrink to narrow');

    await _setSize(tester, const Size(800, 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'at intermediate width');

    await _setSize(tester, const Size(1440, 900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'back to wide');

    // Still a working dashboard with metric cards after the round trip.
    expect(find.byType(MetricCard), findsWidgets);
  });
}
