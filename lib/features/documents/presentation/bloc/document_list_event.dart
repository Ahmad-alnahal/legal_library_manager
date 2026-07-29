import 'package:equatable/equatable.dart';

import '../../domain/entities/document_list_query.dart';
import '../../domain/entities/document_list_item.dart';

sealed class DocumentListEvent extends Equatable {
  const DocumentListEvent();

  @override
  List<Object?> get props => [];
}

class DocumentListStarted extends DocumentListEvent {
  const DocumentListStarted();
}

class DocumentListRefreshed extends DocumentListEvent {
  const DocumentListRefreshed();
}

class DocumentListSearchChanged extends DocumentListEvent {
  const DocumentListSearchChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

class DocumentListFiltersChanged extends DocumentListEvent {
  const DocumentListFiltersChanged(this.filters);

  final DocumentListFilters filters;

  @override
  List<Object?> get props => [filters];
}

class DocumentListSortChanged extends DocumentListEvent {
  const DocumentListSortChanged(this.sort);

  final DocumentListSort sort;

  @override
  List<Object?> get props => [sort];
}

class DocumentListNextPageRequested extends DocumentListEvent {
  const DocumentListNextPageRequested();
}

class DocumentListLoadRequested extends DocumentListEvent {
  const DocumentListLoadRequested(this.requestVersion);

  final int requestVersion;

  @override
  List<Object?> get props => [requestVersion];
}

class DocumentListPageSucceeded extends DocumentListEvent {
  const DocumentListPageSucceeded(this.requestVersion, this.page);

  final int requestVersion;
  final DocumentListPage page;

  @override
  List<Object?> get props => [requestVersion, page];
}

class DocumentListPageFailed extends DocumentListEvent {
  const DocumentListPageFailed(this.requestVersion);

  final int requestVersion;

  @override
  List<Object?> get props => [requestVersion];
}
