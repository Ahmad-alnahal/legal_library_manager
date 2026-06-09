import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/document_list_query.dart';
import '../../domain/repositories/document_list_repository.dart';
import 'document_list_event.dart';
import 'document_list_state.dart';

class DocumentListBloc extends Bloc<DocumentListEvent, DocumentListState> {
  DocumentListBloc({
    required this.repository,
    this.pageSize = 50,
    this.searchDebounce = const Duration(milliseconds: 300),
  }) : super(const DocumentListState()) {
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'must be between 1 and 200',
      );
    }
    on<DocumentListStarted>(_onStarted);
    on<DocumentListRefreshed>(_onRefreshed);
    on<DocumentListSearchChanged>(_onSearchChanged);
    on<DocumentListFiltersChanged>(_onFiltersChanged);
    on<DocumentListSortChanged>(_onSortChanged);
    on<DocumentListNextPageRequested>(_onNextPage);
    on<DocumentListSelectionToggled>(_onSelectionToggled);
    on<DocumentListSelectionCleared>(_onSelectionCleared);
    on<DocumentListLoadRequested>(_onLoadRequested);
    on<DocumentListPageSucceeded>(_onPageSucceeded);
    on<DocumentListPageFailed>(_onPageFailed);
  }

  final DocumentListRepository repository;
  final int pageSize;
  final Duration searchDebounce;

  Timer? _searchTimer;
  int _requestVersion = 0;

  void _onStarted(DocumentListStarted event, Emitter<DocumentListState> emit) {
    if (state.status != DocumentListStatus.initial) return;
    _requestFirstPage();
  }

  void _onRefreshed(
    DocumentListRefreshed event,
    Emitter<DocumentListState> emit,
  ) {
    _searchTimer?.cancel();
    _requestFirstPage();
  }

  void _onSearchChanged(
    DocumentListSearchChanged event,
    Emitter<DocumentListState> emit,
  ) {
    _searchTimer?.cancel();
    final value = event.value.trim();
    final filters = state.filters.copyWith(
      search: value,
      clearSearch: value.isEmpty,
    );
    emit(state.copyWith(filters: filters, selectedIds: const {}));

    // Invalidate any in-flight response immediately, before the debounce fires.
    final version = ++_requestVersion;
    _searchTimer = Timer(searchDebounce, () {
      if (!isClosed) add(DocumentListLoadRequested(version));
    });
  }

  void _onFiltersChanged(
    DocumentListFiltersChanged event,
    Emitter<DocumentListState> emit,
  ) {
    _searchTimer?.cancel();
    emit(
      state.copyWith(
        filters: event.filters.normalized(),
        selectedIds: const {},
      ),
    );
    _requestFirstPage();
  }

  void _onSortChanged(
    DocumentListSortChanged event,
    Emitter<DocumentListState> emit,
  ) {
    if (event.sort == state.sort) return;
    _searchTimer?.cancel();
    emit(state.copyWith(sort: event.sort, selectedIds: const {}));
    _requestFirstPage();
  }

  void _onLoadRequested(
    DocumentListLoadRequested event,
    Emitter<DocumentListState> emit,
  ) {
    if (event.requestVersion != _requestVersion) return;
    emit(
      state.copyWith(
        status: DocumentListStatus.loading,
        items: const [],
        totalCount: 0,
        isLoadingMore: false,
        clearError: true,
      ),
    );
    final query = DocumentListQuery(
      filters: state.filters,
      sort: state.sort,
      limit: pageSize,
    );
    unawaited(_loadFirstPage(event.requestVersion, query));
  }

  Future<void> _loadFirstPage(
    int requestVersion,
    DocumentListQuery query,
  ) async {
    try {
      final page = await repository.getDocuments(query);
      if (!isClosed) add(DocumentListPageSucceeded(requestVersion, page));
    } catch (_) {
      if (!isClosed) add(DocumentListPageFailed(requestVersion));
    }
  }

  void _onPageSucceeded(
    DocumentListPageSucceeded event,
    Emitter<DocumentListState> emit,
  ) {
    if (event.requestVersion != _requestVersion) return;
    emit(
      state.copyWith(
        status: DocumentListStatus.success,
        items: event.page.items,
        totalCount: event.page.totalCount,
        clearError: true,
      ),
    );
  }

  void _onPageFailed(
    DocumentListPageFailed event,
    Emitter<DocumentListState> emit,
  ) {
    if (event.requestVersion != _requestVersion) return;
    emit(
      state.copyWith(
        status: DocumentListStatus.failure,
        items: const [],
        totalCount: 0,
        errorMessage: 'document_list_load_failed',
      ),
    );
  }

  Future<void> _onNextPage(
    DocumentListNextPageRequested event,
    Emitter<DocumentListState> emit,
  ) async {
    if (state.status != DocumentListStatus.success ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    final version = _requestVersion;
    emit(state.copyWith(isLoadingMore: true, clearError: true));
    final query = DocumentListQuery(
      filters: state.filters,
      sort: state.sort,
      offset: state.items.length,
      limit: pageSize,
    );
    try {
      final page = await repository.getDocuments(query);
      if (version != _requestVersion || emit.isDone) return;
      emit(
        state.copyWith(
          items: [...state.items, ...page.items],
          totalCount: page.totalCount,
          isLoadingMore: false,
          clearError: true,
        ),
      );
    } catch (_) {
      if (version != _requestVersion || emit.isDone) return;
      emit(
        state.copyWith(
          isLoadingMore: false,
          errorMessage: 'document_list_next_page_failed',
        ),
      );
    }
  }

  void _onSelectionToggled(
    DocumentListSelectionToggled event,
    Emitter<DocumentListState> emit,
  ) {
    final selected = {...state.selectedIds};
    if (!selected.add(event.documentId)) selected.remove(event.documentId);
    emit(state.copyWith(selectedIds: selected));
  }

  void _onSelectionCleared(
    DocumentListSelectionCleared event,
    Emitter<DocumentListState> emit,
  ) {
    if (state.selectedIds.isEmpty) return;
    emit(state.copyWith(selectedIds: const {}));
  }

  void _requestFirstPage() {
    final version = ++_requestVersion;
    add(DocumentListLoadRequested(version));
  }

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _requestVersion++;
    return super.close();
  }
}
