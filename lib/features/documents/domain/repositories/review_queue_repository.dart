// lib/features/documents/domain/repositories/review_queue_repository.dart

import '../entities/review_queue_item.dart';
import '../entities/review_queue_query.dart';

/// Read-only, persistence-agnostic contract for the document review queue.
///
/// Implementations page at the database level (LIMIT/OFFSET) and never load the
/// full library into memory. Ordering is fixed and deterministic so pagination
/// is stable across calls. This contract is read-only by design; workflow
/// mutations go through the metadata repository / use cases.
abstract class ReviewQueueRepository {
  /// Returns one page of the queue described by [query]. Throws [ArgumentError]
  /// for an invalid page window (negative offset or out-of-range limit).
  Future<ReviewQueuePage> getQueue(ReviewQueueQuery query);
}
