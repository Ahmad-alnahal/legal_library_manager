// lib/features/duplicates/domain/entities/duplicate_group_summary.dart

import 'package:equatable/equatable.dart';

/// One page of duplicate groups returned by [DuplicateReviewRepository].
class DuplicateGroupPage {
  const DuplicateGroupPage({
    required this.groups,
    required this.totalCount,
    required this.pendingReviewCount,
    required this.offset,
    required this.limit,
  });

  final List<DuplicateGroupSummary> groups;
  final int totalCount;
  final int pendingReviewCount;
  final int offset;
  final int limit;

  bool get hasMore => offset + groups.length < totalCount;
}

/// A read-only summary of one duplicate group — used in the group list.
class DuplicateGroupSummary extends Equatable {
  const DuplicateGroupSummary({
    required this.id,
    required this.groupCode,
    required this.sha256Hash,
    required this.reviewStatusKey,
    required this.memberCount,
    this.displayName,
    this.preferredFileId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String groupCode;
  final String sha256Hash;
  final String reviewStatusKey;
  final int memberCount;
  final String? displayName;
  final int? preferredFileId;
  final String createdAt;
  final String updatedAt;

  /// First 16 hex characters — enough for visual identification in the UI.
  /// User-facing label for this duplicate group.
  ///
  /// The technical [groupCode] stays stable for audit/debugging, but the UI
  /// should lead with the best available duplicated document/file title.
  String get userLabel {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return groupCode;
  }

  String get sha256Short =>
      sha256Hash.length > 16 ? '${sha256Hash.substring(0, 16)}…' : sha256Hash;

  @override
  List<Object?> get props => [
    id,
    groupCode,
    sha256Hash,
    reviewStatusKey,
    memberCount,
    displayName,
    preferredFileId,
    createdAt,
    updatedAt,
  ];
}
