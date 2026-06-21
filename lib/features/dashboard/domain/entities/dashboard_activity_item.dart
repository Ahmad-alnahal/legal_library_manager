// lib/features/dashboard/domain/entities/dashboard_activity_item.dart

import 'package:equatable/equatable.dart';

import 'activity_source.dart';

/// A single recent safe activity record shown on the dashboard.
///
/// Only append-only, audit-safe fields from file_events, file_open_events,
/// and import_batches are included. Document contents and raw error details
/// are never exposed.
class DashboardActivityItem extends Equatable {
  const DashboardActivityItem({
    required this.source,
    required this.eventKey,
    this.documentId,
    this.fileId,
    this.batchCode,
    this.resultKey,
    required this.timestamp,
  });

  final ActivitySource source;

  /// Event type key (file_events), open_target_key (file_open_events),
  /// or 'import_batch' (import_batches).
  final String eventKey;

  final int? documentId;
  final int? fileId;

  /// Batch code when the record comes from import_batches.
  final String? batchCode;

  /// Result/status key when available (e.g. 'succeeded', 'failed', 'started').
  final String? resultKey;

  final DateTime timestamp;

  @override
  List<Object?> get props => [
    source,
    eventKey,
    documentId,
    fileId,
    batchCode,
    resultKey,
    timestamp,
  ];
}
