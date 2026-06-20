// lib/features/duplicates/domain/repositories/duplicate_review_repository.dart

import '../entities/duplicate_group_details.dart';
import '../entities/duplicate_group_summary.dart';

/// Contract for duplicate-group review.
///
/// M9.2 permits metadata-only review decisions. Implementations must never
/// move, rename, delete, copy, or modify physical files.
abstract class DuplicateReviewRepository {
  Future<DuplicateGroupPage> getGroups({int offset = 0, int limit = 50});
  Future<DuplicateGroupDetails> getGroupDetails(int groupId);

  /// Marks [fileId] as the preferred member for [groupId].
  ///
  /// Throws [StateError] if the group does not exist or the file is not a
  /// member of that group.
  Future<void> setPreferredMember({required int groupId, required int fileId});

  /// Hides or shows a duplicate group member in duplicate-aware search/list
  /// surfaces. This changes only duplicate metadata.
  Future<void> setMemberHidden({
    required int groupId,
    required int fileId,
    required bool hidden,
  });

  /// Updates group review status and optional reviewer notes.
  ///
  /// [statusKey] must be one of `unreviewed`, `reviewed`, or
  /// `archived_for_later`.
  Future<void> updateReview({
    required int groupId,
    required String statusKey,
    String? notes,
  });
}
