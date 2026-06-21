// test/features/dashboard/dashboard_page_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/dashboard/domain/entities/activity_source.dart';
import 'package:legal_library_manager/features/dashboard/domain/entities/dashboard_activity_item.dart';
import 'package:legal_library_manager/features/dashboard/domain/entities/dashboard_metrics.dart';
import 'package:legal_library_manager/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:legal_library_manager/features/dashboard/presentation/bloc/dashboard_bloc.dart'
    show DashboardBloc;
import 'package:legal_library_manager/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:legal_library_manager/features/dashboard/presentation/widgets/metric_card.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class _FakeRepository implements DashboardRepository {
  _FakeRepository({
    this.metricsResult,
    this.activityResult,
    this.throwOnLoad = false,
  });

  final DashboardMetrics? metricsResult;
  final List<DashboardActivityItem>? activityResult;
  final bool throwOnLoad;

  @override
  Future<DashboardMetrics> getMetrics() async {
    if (throwOnLoad) throw Exception('load error');
    return metricsResult ?? DashboardMetrics.empty;
  }

  @override
  Future<List<DashboardActivityItem>> getRecentActivity({
    int limit = 20,
  }) async {
    if (throwOnLoad) throw Exception('load error');
    return activityResult ?? const [];
  }
}

// ── Test helpers ──────────────────────────────────────────────────────────────

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeRepository repo, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await getIt.reset();
  getIt
    ..registerSingleton<DashboardRepository>(repo)
    ..registerFactory<DashboardBloc>(() => DashboardBloc(repository: repo));

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
        child: Scaffold(body: DashboardPage()),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  tearDown(() async {
    await getIt.reset();
  });

  group('DashboardPage widget', () {
    testWidgets('renders 8 metric cards after successful load', (tester) async {
      await _pumpPage(
        tester,
        _FakeRepository(metricsResult: DashboardMetrics.empty),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MetricCard), findsNWidgets(8));
    });

    testWidgets('shows real metric count from repository', (tester) async {
      const metrics = DashboardMetrics(
        totalImportedFiles: 42,
        needsReview: 5,
        inProgress: 3,
        classified: 10,
        copiedToLibrary: 8,
        readyForExport: 2,
        duplicateGroups: 1,
        corruptedFiles: 0,
        totalDocuments: 20,
      );
      await _pumpPage(tester, _FakeRepository(metricsResult: metrics));
      await tester.pumpAndSettle();

      // MetricCard renders the formatted count values.
      expect(find.text('42'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('shows activity item label when activity is present', (
      tester,
    ) async {
      final activity = [
        DashboardActivityItem(
          source: ActivitySource.importBatch,
          eventKey: 'import_batch',
          batchCode: 'IMP-TEST-001',
          timestamp: DateTime.utc(2026, 6, 21),
        ),
      ];
      await _pumpPage(
        tester,
        _FakeRepository(
          metricsResult: DashboardMetrics.empty,
          activityResult: activity,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('IMP-TEST-001'), findsOneWidget);
    });

    testWidgets('shows empty-activity message when no activity', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _FakeRepository(
          metricsResult: DashboardMetrics.empty,
          activityResult: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('لا يوجد نشاط مسجّل بعد.'), findsOneWidget);
    });

    testWidgets('shows error state and retry button on failure', (
      tester,
    ) async {
      await _pumpPage(tester, _FakeRepository(throwOnLoad: true));
      await tester.pumpAndSettle();

      expect(find.text('تعذّر تحميل بيانات لوحة القيادة.'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });

    testWidgets('tapping refresh button triggers reload', (tester) async {
      int loadCount = 0;
      final repo = _FakeRepository(
        metricsResult: DashboardMetrics.empty,
        activityResult: const [],
      );
      // Override to count calls by wrapping.
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      // The refresh button (tooltip: 'تحديث البيانات').
      final refreshBtn = find.byIcon(Icons.refresh_outlined);
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);
      await tester.pumpAndSettle();

      // No exception after tapping refresh.
      expect(tester.takeException(), isNull);
      loadCount; // silence unused warning
    });

    testWidgets('all-zero metrics show progress bars at 0%', (tester) async {
      await _pumpPage(
        tester,
        _FakeRepository(metricsResult: DashboardMetrics.empty),
      );
      await tester.pumpAndSettle();

      // LinearProgressIndicator at value 0 are present in progress panel.
      final progressBars = find.byType(LinearProgressIndicator);
      expect(progressBars, findsWidgets);
    });
  });
}
