// lib/features/dashboard/domain/repositories/dashboard_repository.dart

import '../entities/dashboard_activity_item.dart';
import '../entities/dashboard_metrics.dart';

/// Read-only contract for dashboard data.
///
/// Implementations must never mutate documents, files, settings, roots,
/// backups, or event records. All methods return a snapshot; they do not
/// provide streams or reactive updates.
abstract class DashboardRepository {
  /// Returns a single snapshot of all operational metrics.
  Future<DashboardMetrics> getMetrics();

  /// Returns the [limit] most recent safe activity records in newest-first
  /// order, sourced from file_events, file_open_events, and import_batches.
  Future<List<DashboardActivityItem>> getRecentActivity({int limit = 20});
}
