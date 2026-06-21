// lib/features/dashboard/presentation/bloc/dashboard_state.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/dashboard_activity_item.dart';
import '../../domain/entities/dashboard_metrics.dart';
import 'dashboard_status.dart';

class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.metrics,
    this.recentActivity = const [],
  });

  final DashboardStatus status;
  final DashboardMetrics? metrics;
  final List<DashboardActivityItem> recentActivity;

  bool get isLoading => status == DashboardStatus.loading;
  bool get isSuccess => status == DashboardStatus.success;
  bool get isFailure => status == DashboardStatus.failure;

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardMetrics? metrics,
    List<DashboardActivityItem>? recentActivity,
  }) => DashboardState(
    status: status ?? this.status,
    metrics: metrics ?? this.metrics,
    recentActivity: recentActivity ?? this.recentActivity,
  );

  @override
  List<Object?> get props => [status, metrics, recentActivity];
}
