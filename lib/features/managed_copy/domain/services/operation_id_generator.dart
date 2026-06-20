// lib/features/managed_copy/domain/services/operation_id_generator.dart

/// Generates unique, filename-safe operation IDs for managed-copy runs.
///
/// Implementations must guarantee that two calls at the same wall-clock
/// millisecond still produce distinct IDs (i.e., they must not rely on
/// millisecond timestamps alone). IDs are embedded in temporary filenames
/// and in file_events.operation_id; they must not contain characters
/// forbidden in Windows filenames (/, \, :, *, ?, ", <, >, |).
abstract class OperationIdGenerator {
  /// Returns a new, unique, filename-safe operation ID anchored to [now].
  String generate(DateTime now);
}
