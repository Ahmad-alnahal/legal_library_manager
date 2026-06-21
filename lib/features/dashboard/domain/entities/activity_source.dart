// lib/features/dashboard/domain/entities/activity_source.dart

/// Which append-only audit table a dashboard activity record originated from.
enum ActivitySource { fileEvent, fileOpenEvent, importBatch }
