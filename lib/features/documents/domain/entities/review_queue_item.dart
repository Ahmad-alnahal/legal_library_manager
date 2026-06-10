// lib/features/documents/domain/entities/review_queue_item.dart

import 'package:equatable/equatable.dart';

/// A lightweight row in the review queue list.
///
/// Intentionally smaller than `DocumentListItem`: the queue panel only needs
/// enough to render and pick a row, so this avoids loading the heavier list
/// projection (duplicate/health indicators, categories, etc.). Persistence
/// agnostic.
class ReviewQueueItem extends Equatable {
  const ReviewQueueItem({
    required this.id,
    required this.workflowStatusKey,
    required this.updatedAt,
    this.documentCode,
    this.title,
    this.sourceFileName,
    this.documentTypeNameAr,
  });

  final int id;
  final String workflowStatusKey;
  final String updatedAt;
  final String? documentCode;
  final String? title;
  final String? sourceFileName;
  final String? documentTypeNameAr;

  @override
  List<Object?> get props => [
    id,
    workflowStatusKey,
    updatedAt,
    documentCode,
    title,
    sourceFileName,
    documentTypeNameAr,
  ];
}

/// One page of review-queue results plus the total count of matching documents,
/// so callers can lazily page without ever loading the full library.
class ReviewQueuePage extends Equatable {
  const ReviewQueuePage({
    required this.items,
    required this.totalCount,
    required this.offset,
    required this.limit,
  });

  final List<ReviewQueueItem> items;
  final int totalCount;
  final int offset;
  final int limit;

  bool get hasMore => offset + items.length < totalCount;

  @override
  List<Object?> get props => [items, totalCount, offset, limit];
}
