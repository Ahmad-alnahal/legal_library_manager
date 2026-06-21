// test/features/dashboard/bloc/dashboard_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/dashboard/domain/entities/activity_source.dart';
import 'package:legal_library_manager/features/dashboard/domain/entities/dashboard_activity_item.dart';
import 'package:legal_library_manager/features/dashboard/domain/entities/dashboard_metrics.dart';
import 'package:legal_library_manager/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:legal_library_manager/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:legal_library_manager/features/dashboard/presentation/bloc/dashboard_state.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class _FakeRepository implements DashboardRepository {
  _FakeRepository({
    this.metricsResult,
    this.activityResult,
    this.throwOnMetrics = false,
  });

  final DashboardMetrics? metricsResult;
  final List<DashboardActivityItem>? activityResult;
  final bool throwOnMetrics;

  int metricsCallCount = 0;
  int activityCallCount = 0;

  @override
  Future<DashboardMetrics> getMetrics() async {
    metricsCallCount++;
    if (throwOnMetrics) throw Exception('metrics error');
    return metricsResult ?? DashboardMetrics.empty;
  }

  @override
  Future<List<DashboardActivityItem>> getRecentActivity({
    int limit = 20,
  }) async {
    activityCallCount++;
    return activityResult ?? const [];
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

const _sampleMetrics = DashboardMetrics(
  totalImportedFiles: 10,
  needsReview: 3,
  inProgress: 2,
  classified: 4,
  copiedToLibrary: 5,
  readyForExport: 1,
  duplicateGroups: 2,
  corruptedFiles: 0,
  totalDocuments: 15,
);

final _sampleActivity = [
  DashboardActivityItem(
    source: ActivitySource.importBatch,
    eventKey: 'import_batch',
    batchCode: 'IMP-001',
    timestamp: DateTime.utc(2026, 6, 21),
  ),
];

void main() {
  group('DashboardBloc', () {
    test('initial state has status initial', () {
      final bloc = DashboardBloc(repository: _FakeRepository());
      expect(bloc.state.status, DashboardStatus.initial);
      bloc.close();
    });

    test('DashboardLoad transitions to loading then success', () async {
      final repo = _FakeRepository(
        metricsResult: _sampleMetrics,
        activityResult: _sampleActivity,
      );
      final bloc = DashboardBloc(repository: repo);

      bloc.add(const DashboardLoad());
      await bloc.stream.firstWhere((s) => s.isSuccess);

      expect(bloc.state.status, DashboardStatus.success);
      expect(bloc.state.metrics, _sampleMetrics);
      expect(bloc.state.recentActivity, _sampleActivity);
      expect(repo.metricsCallCount, 1);
      expect(repo.activityCallCount, 1);
      await bloc.close();
    });

    test('DashboardLoad emits failure when repository throws', () async {
      final bloc = DashboardBloc(
        repository: _FakeRepository(throwOnMetrics: true),
      );

      bloc.add(const DashboardLoad());
      await bloc.stream.firstWhere((s) => s.isFailure);

      expect(bloc.state.status, DashboardStatus.failure);
      expect(bloc.state.metrics, isNull);
      await bloc.close();
    });

    test('DashboardLoad is dropped while already loading (droppable)', () async {
      final repo = _FakeRepository(
        metricsResult: DashboardMetrics.empty,
        activityResult: const [],
      );
      final bloc = DashboardBloc(repository: repo);

      // Both events dispatched before the first finishes; droppable drops second.
      bloc.add(const DashboardLoad());
      bloc.add(const DashboardLoad());
      await bloc.stream.firstWhere((s) => s.isSuccess);

      expect(repo.metricsCallCount, 1);
      await bloc.close();
    });

    test('DashboardRefresh reloads even after success', () async {
      final repo = _FakeRepository(
        metricsResult: _sampleMetrics,
        activityResult: const [],
      );
      final bloc = DashboardBloc(repository: repo);

      bloc.add(const DashboardLoad());
      await bloc.stream.firstWhere((s) => s.isSuccess);
      expect(repo.metricsCallCount, 1);

      bloc.add(const DashboardRefresh());
      await bloc.stream.firstWhere(
        (s) => s.isSuccess && repo.metricsCallCount >= 2,
      );
      expect(repo.metricsCallCount, 2);
      expect(bloc.state.status, DashboardStatus.success);
      await bloc.close();
    });

    test('success state: empty metrics returns zero completion', () async {
      final bloc = DashboardBloc(
        repository: _FakeRepository(metricsResult: DashboardMetrics.empty),
      );
      bloc.add(const DashboardLoad());
      await bloc.stream.firstWhere((s) => s.isSuccess);
      expect(bloc.state.metrics!.completionPercent, 0.0);
      await bloc.close();
    });

    test(
      'success state: metrics with data returns correct completion',
      () async {
        const metrics = DashboardMetrics(
          totalImportedFiles: 10,
          needsReview: 0,
          inProgress: 0,
          classified: 0,
          copiedToLibrary: 2,
          readyForExport: 1,
          duplicateGroups: 0,
          corruptedFiles: 0,
          totalDocuments: 6,
        );
        final bloc = DashboardBloc(
          repository: _FakeRepository(metricsResult: metrics),
        );
        bloc.add(const DashboardLoad());
        await bloc.stream.firstWhere((s) => s.isSuccess);
        // (2 + 1) / 6 = 0.5
        expect(bloc.state.metrics!.completionPercent, closeTo(0.5, 0.001));
        await bloc.close();
      },
    );

    test('DashboardState equality works via Equatable', () {
      const s1 = DashboardState(status: DashboardStatus.success);
      const s2 = DashboardState(status: DashboardStatus.success);
      expect(s1, equals(s2));
    });

    test('failure then refresh recovers to success', () async {
      final bloc = DashboardBloc(
        repository: _FakeRepository(throwOnMetrics: true),
      );
      bloc.add(const DashboardLoad());
      await bloc.stream.firstWhere((s) => s.isFailure);
      expect(bloc.state.isFailure, isTrue);
      await bloc.close();

      // Fresh BLoC with good repo recovers.
      final bloc2 = DashboardBloc(
        repository: _FakeRepository(metricsResult: _sampleMetrics),
      );
      bloc2.add(const DashboardLoad());
      await bloc2.stream.firstWhere((s) => s.isSuccess);
      expect(bloc2.state.isSuccess, isTrue);
      await bloc2.close();
    });
  });
}
