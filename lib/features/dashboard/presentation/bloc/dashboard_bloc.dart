// lib/features/dashboard/presentation/bloc/dashboard_bloc.dart

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/dashboard_activity_item.dart';
import '../../domain/entities/dashboard_metrics.dart';
import '../../domain/repositories/dashboard_repository.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import 'dashboard_status.dart';

export 'dashboard_event.dart';
export 'dashboard_status.dart';

/// Loads and refreshes dashboard metrics and recent activity.
///
/// The presentation layer must not import Drift, dart:io, or any filesystem /
/// process API. This BLoC receives only domain types through [DashboardRepository].
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc({required this.repository}) : super(const DashboardState()) {
    on<DashboardLoad>(_onLoad, transformer: droppable());
    on<DashboardRefresh>(_onRefresh, transformer: restartable());
  }

  final DashboardRepository repository;

  int _version = 0;

  Future<void> _onLoad(DashboardLoad _, Emitter<DashboardState> emit) async {
    final version = ++_version;
    emit(const DashboardState(status: DashboardStatus.loading));
    await _fetch(version, emit);
  }

  Future<void> _onRefresh(
    DashboardRefresh _,
    Emitter<DashboardState> emit,
  ) async {
    final version = ++_version;
    emit(const DashboardState(status: DashboardStatus.loading));
    await _fetch(version, emit);
  }

  Future<void> _fetch(int version, Emitter<DashboardState> emit) async {
    try {
      final DashboardMetrics metrics = await repository.getMetrics();
      if (isClosed || version != _version) return;
      final List<DashboardActivityItem> activity = await repository
          .getRecentActivity();
      if (isClosed || version != _version) return;
      emit(
        DashboardState(
          status: DashboardStatus.success,
          metrics: metrics,
          recentActivity: activity,
        ),
      );
    } catch (_) {
      if (isClosed || version != _version) return;
      emit(state.copyWith(status: DashboardStatus.failure));
    }
  }

  @override
  Future<void> close() {
    _version++;
    return super.close();
  }
}
