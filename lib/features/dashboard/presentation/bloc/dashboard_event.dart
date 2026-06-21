// lib/features/dashboard/presentation/bloc/dashboard_event.dart

import 'package:equatable/equatable.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// Load metrics and recent activity on first open. Skipped if already loading.
class DashboardLoad extends DashboardEvent {
  const DashboardLoad();
}

/// Force-reload metrics and recent activity regardless of current status.
class DashboardRefresh extends DashboardEvent {
  const DashboardRefresh();
}
