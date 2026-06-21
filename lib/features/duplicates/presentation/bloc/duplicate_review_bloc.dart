// lib/features/duplicates/presentation/bloc/duplicate_review_bloc.dart

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/duplicate_review_repository.dart';
import 'duplicate_review_event.dart';
import 'duplicate_review_state.dart';

class DuplicateReviewBloc
    extends Bloc<DuplicateReviewEvent, DuplicateReviewState> {
  DuplicateReviewBloc({required this.repository, this.pageSize = 50})
    : super(const DuplicateReviewState()) {
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'must be between 1 and 200',
      );
    }
    on<DuplicateReviewStarted>(_onStarted);
    on<DuplicateReviewRefreshed>(_onRefreshed);
    on<DuplicateReviewNextPageRequested>(_onNextPage);
    on<DuplicateReviewGroupSelected>(_onGroupSelected);
    on<DuplicateReviewPageLoaded>(_onPageLoaded);
    on<DuplicateReviewPageFailed>(_onPageFailed);
    on<DuplicateReviewDetailsLoaded>(_onDetailsLoaded);
    on<DuplicateReviewDetailsFailed>(_onDetailsFailed);
    on<DuplicateReviewPreferredMemberSet>(_onPreferredMemberSet);
    on<DuplicateReviewMemberHiddenSet>(_onMemberHiddenSet);
    on<DuplicateReviewGroupReviewSaved>(_onGroupReviewSaved);
  }

  final DuplicateReviewRepository repository;
  final int pageSize;

  int _listVersion = 0;
  int _detailVersion = 0;

  void _onStarted(
    DuplicateReviewStarted _,
    Emitter<DuplicateReviewState> emit,
  ) {
    if (state.listStatus != DuplicateListStatus.initial) return;
    _requestFirstPage(emit);
  }

  void _onRefreshed(
    DuplicateReviewRefreshed _,
    Emitter<DuplicateReviewState> emit,
  ) {
    _requestFirstPage(emit);
  }

  void _requestFirstPage(Emitter<DuplicateReviewState> emit) {
    final version = ++_listVersion;
    ++_detailVersion; // invalidate any in-flight detail load
    emit(
      state.copyWith(
        listStatus: DuplicateListStatus.loading,
        groups: const [],
        totalCount: 0,
        pendingReviewCount: 0,
        isLoadingMore: false,
        operation: DuplicateReviewOperation.none,
        clearListError: true,
        clearMessage: true,
      ),
    );
    unawaited(_loadPage(version));
  }

  Future<void> _loadPage(int version) async {
    try {
      final page = await repository.getGroups(limit: pageSize);
      if (!isClosed) add(DuplicateReviewPageLoaded(version, page));
    } catch (_) {
      if (!isClosed) add(DuplicateReviewPageFailed(version));
    }
  }

  void _onGroupSelected(
    DuplicateReviewGroupSelected event,
    Emitter<DuplicateReviewState> emit,
  ) {
    if (state.selectedGroupId == event.groupId &&
        state.detailStatus == DuplicateDetailStatus.success) {
      return;
    }
    final version = ++_detailVersion;
    emit(
      state.copyWith(
        selectedGroupId: event.groupId,
        detailStatus: DuplicateDetailStatus.loading,
        clearSelectedDetails: true,
      ),
    );
    unawaited(_loadDetails(version, event.groupId));
  }

  Future<void> _loadDetails(int version, int groupId) async {
    try {
      final details = await repository.getGroupDetails(groupId);
      if (!isClosed) add(DuplicateReviewDetailsLoaded(version, details));
    } catch (_) {
      if (!isClosed) add(DuplicateReviewDetailsFailed(version));
    }
  }

  void _onPageLoaded(
    DuplicateReviewPageLoaded event,
    Emitter<DuplicateReviewState> emit,
  ) {
    if (event.requestVersion != _listVersion) return;
    emit(
      state.copyWith(
        listStatus: DuplicateListStatus.success,
        groups: event.page.groups,
        totalCount: event.page.totalCount,
        pendingReviewCount: event.page.pendingReviewCount,
        clearListError: true,
      ),
    );
  }

  void _onPageFailed(
    DuplicateReviewPageFailed event,
    Emitter<DuplicateReviewState> emit,
  ) {
    if (event.requestVersion != _listVersion) return;
    emit(
      state.copyWith(
        listStatus: DuplicateListStatus.failure,
        groups: const [],
        totalCount: 0,
        pendingReviewCount: 0,
        listError: 'duplicate_review_load_failed',
      ),
    );
  }

  Future<void> _onNextPage(
    DuplicateReviewNextPageRequested _,
    Emitter<DuplicateReviewState> emit,
  ) async {
    if (state.listStatus != DuplicateListStatus.success ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    final version = _listVersion;
    emit(state.copyWith(isLoadingMore: true, clearListError: true));
    try {
      final page = await repository.getGroups(
        offset: state.groups.length,
        limit: pageSize,
      );
      if (version != _listVersion || emit.isDone) return;
      emit(
        state.copyWith(
          groups: [...state.groups, ...page.groups],
          totalCount: page.totalCount,
          pendingReviewCount: page.pendingReviewCount,
          isLoadingMore: false,
          operation: DuplicateReviewOperation.none,
          clearListError: true,
        ),
      );
    } catch (_) {
      if (version != _listVersion || emit.isDone) return;
      emit(
        state.copyWith(
          isLoadingMore: false,
          listError: 'duplicate_review_next_page_failed',
        ),
      );
    }
  }

  void _onDetailsLoaded(
    DuplicateReviewDetailsLoaded event,
    Emitter<DuplicateReviewState> emit,
  ) {
    if (event.requestVersion != _detailVersion) return;
    emit(
      state.copyWith(
        detailStatus: DuplicateDetailStatus.success,
        selectedDetails: event.details,
      ),
    );
  }

  void _onDetailsFailed(
    DuplicateReviewDetailsFailed event,
    Emitter<DuplicateReviewState> emit,
  ) {
    if (event.requestVersion != _detailVersion) return;
    emit(
      state.copyWith(
        detailStatus: DuplicateDetailStatus.failure,
        clearSelectedDetails: true,
      ),
    );
  }

  Future<void> _onPreferredMemberSet(
    DuplicateReviewPreferredMemberSet event,
    Emitter<DuplicateReviewState> emit,
  ) async {
    if (state.isBusy) return;
    emit(
      state.copyWith(
        operation: DuplicateReviewOperation.savingPreferred,
        clearMessage: true,
      ),
    );
    try {
      await repository.setPreferredMember(
        groupId: event.groupId,
        fileId: event.fileId,
      );
      await _reloadAfterDecision(
        event.groupId,
        emit,
        messageKey: 'duplicate_preferred_saved',
      );
    } catch (_) {
      _emitOperationFailure(emit, 'duplicate_preferred_failed');
    }
  }

  Future<void> _onMemberHiddenSet(
    DuplicateReviewMemberHiddenSet event,
    Emitter<DuplicateReviewState> emit,
  ) async {
    if (state.isBusy) return;
    emit(
      state.copyWith(
        operation: DuplicateReviewOperation.savingVisibility,
        clearMessage: true,
      ),
    );
    try {
      await repository.setMemberHidden(
        groupId: event.groupId,
        fileId: event.fileId,
        hidden: event.hidden,
      );
      await _reloadAfterDecision(
        event.groupId,
        emit,
        messageKey: event.hidden
            ? 'duplicate_member_hidden'
            : 'duplicate_member_unhidden',
      );
    } catch (_) {
      _emitOperationFailure(emit, 'duplicate_visibility_failed');
    }
  }

  Future<void> _onGroupReviewSaved(
    DuplicateReviewGroupReviewSaved event,
    Emitter<DuplicateReviewState> emit,
  ) async {
    if (state.isBusy) return;
    emit(
      state.copyWith(
        operation: DuplicateReviewOperation.savingReview,
        clearMessage: true,
      ),
    );
    try {
      await repository.updateReview(
        groupId: event.groupId,
        statusKey: event.statusKey,
        notes: event.notes,
      );
      await _reloadAfterDecision(
        event.groupId,
        emit,
        messageKey: 'duplicate_review_saved',
      );
    } catch (_) {
      _emitOperationFailure(emit, 'duplicate_review_save_failed');
    }
  }

  Future<void> _reloadAfterDecision(
    int groupId,
    Emitter<DuplicateReviewState> emit, {
    required String messageKey,
  }) async {
    final detailVersion = ++_detailVersion;
    final listVersion = ++_listVersion;
    final reloadLimit = state.groups.length > pageSize
        ? state.groups.length
        : pageSize;

    // Confirm the write immediately so the snackbar always reflects the real
    // outcome — if the subsequent reload fails the user still knows the save
    // succeeded rather than seeing a misleading failure message.
    if (!emit.isDone) {
      emit(
        state.copyWith(
          operation: DuplicateReviewOperation.none,
          messageKey: messageKey,
        ),
      );
    }

    try {
      // Reload detail and list in parallel — they are independent reads.
      final (details, page) = await (
        repository.getGroupDetails(groupId),
        repository.getGroups(limit: reloadLimit),
      ).wait;

      if (emit.isDone ||
          detailVersion != _detailVersion ||
          listVersion != _listVersion) {
        return;
      }
      emit(
        state.copyWith(
          listStatus: DuplicateListStatus.success,
          groups: page.groups,
          totalCount: page.totalCount,
          pendingReviewCount: page.pendingReviewCount,
          selectedGroupId: groupId,
          detailStatus: DuplicateDetailStatus.success,
          selectedDetails: details,
          clearListError: true,
        ),
      );
    } catch (_) {
      // Reload failed — data was already saved; let the user retry by
      // re-selecting the group rather than showing a misleading save error.
      if (emit.isDone ||
          detailVersion != _detailVersion ||
          listVersion != _listVersion) {
        return;
      }
      emit(
        state.copyWith(
          detailStatus: DuplicateDetailStatus.failure,
          clearSelectedDetails: true,
        ),
      );
    }
  }

  void _emitOperationFailure(
    Emitter<DuplicateReviewState> emit,
    String messageKey,
  ) {
    if (emit.isDone) return;
    emit(
      state.copyWith(
        operation: DuplicateReviewOperation.none,
        messageKey: messageKey,
      ),
    );
  }

  @override
  Future<void> close() {
    _listVersion++;
    _detailVersion++;
    return super.close();
  }
}
