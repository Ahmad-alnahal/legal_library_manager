// lib/features/duplicates/presentation/bloc/duplicate_review_event.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/duplicate_group_details.dart';
import '../../domain/entities/duplicate_group_summary.dart';

sealed class DuplicateReviewEvent extends Equatable {
  const DuplicateReviewEvent();

  @override
  List<Object?> get props => [];
}

class DuplicateReviewStarted extends DuplicateReviewEvent {
  const DuplicateReviewStarted();
}

class DuplicateReviewRefreshed extends DuplicateReviewEvent {
  const DuplicateReviewRefreshed();
}

class DuplicateReviewNextPageRequested extends DuplicateReviewEvent {
  const DuplicateReviewNextPageRequested();
}

class DuplicateReviewGroupSelected extends DuplicateReviewEvent {
  const DuplicateReviewGroupSelected(this.groupId);

  final int groupId;

  @override
  List<Object?> get props => [groupId];
}

class DuplicateReviewPreferredMemberSet extends DuplicateReviewEvent {
  const DuplicateReviewPreferredMemberSet({
    required this.groupId,
    required this.fileId,
  });

  final int groupId;
  final int fileId;

  @override
  List<Object?> get props => [groupId, fileId];
}

class DuplicateReviewMemberHiddenSet extends DuplicateReviewEvent {
  const DuplicateReviewMemberHiddenSet({
    required this.groupId,
    required this.fileId,
    required this.hidden,
  });

  final int groupId;
  final int fileId;
  final bool hidden;

  @override
  List<Object?> get props => [groupId, fileId, hidden];
}

class DuplicateReviewGroupReviewSaved extends DuplicateReviewEvent {
  const DuplicateReviewGroupReviewSaved({
    required this.groupId,
    required this.statusKey,
    this.notes,
  });

  final int groupId;
  final String statusKey;
  final String? notes;

  @override
  List<Object?> get props => [groupId, statusKey, notes];
}

// Internal: carries page results back from the async load.
class DuplicateReviewPageLoaded extends DuplicateReviewEvent {
  const DuplicateReviewPageLoaded(this.requestVersion, this.page);

  final int requestVersion;
  final DuplicateGroupPage page;

  @override
  List<Object?> get props => [requestVersion, page];
}

// Internal: signals a group-list page load failure.
class DuplicateReviewPageFailed extends DuplicateReviewEvent {
  const DuplicateReviewPageFailed(this.requestVersion);

  final int requestVersion;

  @override
  List<Object?> get props => [requestVersion];
}

// Internal: carries group-detail results back from the async load.
class DuplicateReviewDetailsLoaded extends DuplicateReviewEvent {
  const DuplicateReviewDetailsLoaded(this.requestVersion, this.details);

  final int requestVersion;
  final DuplicateGroupDetails details;

  @override
  List<Object?> get props => [requestVersion, details];
}

// Internal: signals a group-detail load failure.
class DuplicateReviewDetailsFailed extends DuplicateReviewEvent {
  const DuplicateReviewDetailsFailed(this.requestVersion);

  final int requestVersion;

  @override
  List<Object?> get props => [requestVersion];
}
