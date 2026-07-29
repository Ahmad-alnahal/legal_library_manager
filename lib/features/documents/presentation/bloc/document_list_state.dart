import 'package:equatable/equatable.dart';

import '../../domain/entities/document_list_item.dart';
import '../../domain/entities/document_list_query.dart';

enum DocumentListStatus { initial, loading, success, failure }

class DocumentListState extends Equatable {
  const DocumentListState({
    this.status = DocumentListStatus.initial,
    this.items = const [],
    this.totalCount = 0,
    this.filters = const DocumentListFilters(),
    this.sort = DocumentListSort.updatedNewest,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  final DocumentListStatus status;
  final List<DocumentListItem> items;
  final int totalCount;
  final DocumentListFilters filters;
  final DocumentListSort sort;
  final bool isLoadingMore;
  final String? errorMessage;

  bool get hasMore => items.length < totalCount;
  bool get isEmpty => status == DocumentListStatus.success && items.isEmpty;

  DocumentListState copyWith({
    DocumentListStatus? status,
    List<DocumentListItem>? items,
    int? totalCount,
    DocumentListFilters? filters,
    DocumentListSort? sort,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DocumentListState(
      status: status ?? this.status,
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      filters: filters ?? this.filters,
      sort: sort ?? this.sort,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    items,
    totalCount,
    filters,
    sort,
    isLoadingMore,
    errorMessage,
  ];
}
