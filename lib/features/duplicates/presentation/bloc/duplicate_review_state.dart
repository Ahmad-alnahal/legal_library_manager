// lib/features/duplicates/presentation/bloc/duplicate_review_state.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/duplicate_group_details.dart';
import '../../domain/entities/duplicate_group_summary.dart';

enum DuplicateListStatus { initial, loading, success, failure }

enum DuplicateDetailStatus { none, loading, success, failure }

enum DuplicateReviewOperation {
  none,
  savingPreferred,
  savingVisibility,
  savingReview,
}

class DuplicateReviewState extends Equatable {
  const DuplicateReviewState({
    this.listStatus = DuplicateListStatus.initial,
    this.groups = const [],
    this.totalCount = 0,
    this.pendingReviewCount = 0,
    this.isLoadingMore = false,
    this.listError,
    this.selectedGroupId,
    this.detailStatus = DuplicateDetailStatus.none,
    this.selectedDetails,
    this.operation = DuplicateReviewOperation.none,
    this.messageKey,
  });

  final DuplicateListStatus listStatus;
  final List<DuplicateGroupSummary> groups;
  final int totalCount;
  final int pendingReviewCount;
  final bool isLoadingMore;
  final String? listError;
  final int? selectedGroupId;
  final DuplicateDetailStatus detailStatus;
  final DuplicateGroupDetails? selectedDetails;
  final DuplicateReviewOperation operation;
  final String? messageKey;

  bool get hasMore => groups.length < totalCount;
  bool get isEmpty =>
      listStatus == DuplicateListStatus.success && groups.isEmpty;
  bool get isBusy => operation != DuplicateReviewOperation.none;

  DuplicateReviewState copyWith({
    DuplicateListStatus? listStatus,
    List<DuplicateGroupSummary>? groups,
    int? totalCount,
    int? pendingReviewCount,
    bool? isLoadingMore,
    String? listError,
    bool clearListError = false,
    int? selectedGroupId,
    bool clearSelectedGroup = false,
    DuplicateDetailStatus? detailStatus,
    DuplicateGroupDetails? selectedDetails,
    bool clearSelectedDetails = false,
    DuplicateReviewOperation? operation,
    String? messageKey,
    bool clearMessage = false,
  }) {
    return DuplicateReviewState(
      listStatus: listStatus ?? this.listStatus,
      groups: groups ?? this.groups,
      totalCount: totalCount ?? this.totalCount,
      pendingReviewCount: pendingReviewCount ?? this.pendingReviewCount,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      listError: clearListError ? null : listError ?? this.listError,
      selectedGroupId: clearSelectedGroup
          ? null
          : selectedGroupId ?? this.selectedGroupId,
      detailStatus: detailStatus ?? this.detailStatus,
      selectedDetails: clearSelectedDetails
          ? null
          : selectedDetails ?? this.selectedDetails,
      operation: operation ?? this.operation,
      messageKey: clearMessage ? null : messageKey ?? this.messageKey,
    );
  }

  @override
  List<Object?> get props => [
    listStatus,
    groups,
    totalCount,
    pendingReviewCount,
    isLoadingMore,
    listError,
    selectedGroupId,
    detailStatus,
    selectedDetails,
    operation,
    messageKey,
  ];
}
