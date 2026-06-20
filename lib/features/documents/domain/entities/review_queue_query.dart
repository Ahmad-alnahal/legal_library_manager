// lib/features/documents/domain/entities/review_queue_query.dart

import 'package:equatable/equatable.dart';

/// Which slice of the library the review queue exposes.
///
/// - [reviewQueue] is the default working set of documents that still need
///   classification work: `imported`, `needs_review`, and `in_progress`.
/// - [classified] surfaces completed classification work, including documents
///   already copied to the managed library.
enum ReviewQueueScope { reviewQueue, classified }

extension ReviewQueueScopeStatuses on ReviewQueueScope {
  /// The exact workflow-status keys included by this scope. Kept here (domain)
  /// so the BLoC, repository, and tests share one source of truth.
  List<String> get statusKeys => switch (this) {
    ReviewQueueScope.reviewQueue => const [
      'imported',
      'needs_review',
      'in_progress',
    ],
    ReviewQueueScope.classified => const ['classified', 'copied_to_library'],
  };
}

/// A read-only, paginated request for a slice of the review queue.
///
/// Ordering is fixed and deterministic in the repository (ascending document
/// id) so pagination is stable and "the next document" is well defined; only
/// the scope and the page window vary here.
class ReviewQueueQuery extends Equatable {
  const ReviewQueueQuery({
    this.scope = ReviewQueueScope.reviewQueue,
    this.offset = 0,
    this.limit = 50,
  });

  final ReviewQueueScope scope;
  final int offset;
  final int limit;

  ReviewQueueQuery copyWith({
    ReviewQueueScope? scope,
    int? offset,
    int? limit,
  }) {
    return ReviewQueueQuery(
      scope: scope ?? this.scope,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
    );
  }

  @override
  List<Object?> get props => [scope, offset, limit];
}
