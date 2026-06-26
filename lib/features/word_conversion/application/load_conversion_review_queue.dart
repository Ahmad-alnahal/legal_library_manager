// lib/features/word_conversion/application/load_conversion_review_queue.dart

import '../domain/entities/conversion_review_item.dart';
import '../domain/repositories/word_conversion_repository.dart';

/// Loads all conversion records awaiting quality review, newest first.
///
/// Returns an empty list when none are pending. Never throws; callers must
/// handle exceptions for persistence failures.
class LoadConversionReviewQueue {
  const LoadConversionReviewQueue({required this._repository});

  final WordConversionRepository _repository;

  Future<List<ConversionReviewItem>> call() =>
      _repository.loadPendingConversionReviews();
}
