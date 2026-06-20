import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_item.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_query.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_list_repository.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/document_list_bloc.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/document_list_event.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/document_list_state.dart';

void main() {
  DocumentListItem item(int id) => DocumentListItem(
    id: id,
    workflowStatusKey: 'imported',
    trustLevelKey: 'unverified',
    metadataQualityKey: 'low',
    fileCount: 1,
    hasDuplicate: false,
    hasCorruptedFile: false,
    hasUnreadableFile: false,
    updatedAt: '2026-06-09T12:00:00.000Z',
    title: 'وثيقة $id',
  );

  test('starts, loads first page, then appends the next page', () async {
    final repo = FakeDocumentListRepository((query) async {
      final items = query.offset == 0 ? [item(1), item(2)] : [item(3)];
      return DocumentListPage(
        items: items,
        totalCount: 3,
        offset: query.offset,
        limit: query.limit,
      );
    });
    final bloc = DocumentListBloc(repository: repo, pageSize: 2);
    addTearDown(bloc.close);

    bloc.add(const DocumentListStarted());
    await waitFor(bloc, (s) => s.status == DocumentListStatus.success);
    bloc.add(const DocumentListNextPageRequested());
    await waitFor(bloc, (s) => s.items.length == 3);

    expect(bloc.state.items.map((e) => e.id), [1, 2, 3]);
    expect(repo.queries.map((q) => q.offset), [0, 2]);
    expect(bloc.state.hasMore, isFalse);
  });

  test('search waits 300ms and whitespace clears the query', () async {
    final repo = FakeDocumentListRepository(
      (query) async => DocumentListPage(
        items: const [],
        totalCount: 0,
        offset: query.offset,
        limit: query.limit,
      ),
    );
    final bloc = DocumentListBloc(repository: repo);
    addTearDown(bloc.close);

    bloc.add(const DocumentListSearchChanged('  قانون  '));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(repo.queries, isEmpty);
    await waitFor(bloc, (s) => repo.queries.isNotEmpty);
    expect(repo.queries.single.filters.search, 'قانون');

    bloc.add(const DocumentListSearchChanged('   '));
    await waitFor(bloc, (s) => repo.queries.length == 2);
    expect(repo.queries.last.filters.search, isNull);
  });

  test('rapid typing issues only the latest debounced query', () async {
    final repo = FakeDocumentListRepository(
      (query) async => DocumentListPage(
        items: const [],
        totalCount: 0,
        offset: query.offset,
        limit: query.limit,
      ),
    );
    final bloc = DocumentListBloc(repository: repo);
    addTearDown(bloc.close);

    bloc
      ..add(const DocumentListSearchChanged('ق'))
      ..add(const DocumentListSearchChanged('قا'))
      ..add(const DocumentListSearchChanged('قانون'));
    await waitFor(bloc, (s) => repo.queries.isNotEmpty);

    expect(repo.queries, hasLength(1));
    expect(repo.queries.single.filters.search, 'قانون');
  });

  test('a stale response cannot overwrite a newer search', () async {
    final first = Completer<DocumentListPage>();
    final second = Completer<DocumentListPage>();
    final repo = FakeDocumentListRepository((query) {
      return repoCall(query, first: first, second: second);
    });
    final bloc = DocumentListBloc(
      repository: repo,
      searchDebounce: Duration.zero,
    );
    addTearDown(bloc.close);

    bloc.add(const DocumentListStarted());
    await waitUntil(() => repo.queries.length == 1);
    bloc.add(const DocumentListSearchChanged('الأحدث'));
    await waitUntil(() => repo.queries.length == 2);

    second.complete(
      DocumentListPage(items: [item(2)], totalCount: 1, offset: 0, limit: 50),
    );
    await waitFor(bloc, (s) => s.items.isNotEmpty);
    first.complete(
      DocumentListPage(items: [item(1)], totalCount: 1, offset: 0, limit: 50),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bloc.state.items.single.id, 2);
  });

  test('filters, sort, selection, and failures update state safely', () async {
    var fail = false;
    final repo = FakeDocumentListRepository((query) async {
      if (fail) throw StateError('db failed');
      return DocumentListPage(
        items: [item(1)],
        totalCount: 1,
        offset: query.offset,
        limit: query.limit,
      );
    });
    final bloc = DocumentListBloc(repository: repo);
    addTearDown(bloc.close);

    bloc.add(
      const DocumentListFiltersChanged(
        DocumentListFilters(workflowStatusKey: 'classified'),
      ),
    );
    await waitFor(bloc, (s) => s.status == DocumentListStatus.success);
    expect(repo.queries.last.filters.workflowStatusKey, 'classified');

    bloc.add(const DocumentListSortChanged(DocumentListSort.titleAscending));
    await waitFor(bloc, (s) => repo.queries.length == 2);
    expect(repo.queries.last.sort, DocumentListSort.titleAscending);

    bloc.add(const DocumentListSelectionToggled(1));
    await waitFor(bloc, (s) => s.selectedIds.contains(1));
    bloc.add(const DocumentListSearchChanged('new query'));
    await waitFor(bloc, (s) => s.selectedIds.isEmpty);

    fail = true;
    bloc.add(const DocumentListRefreshed());
    await waitFor(bloc, (s) => s.status == DocumentListStatus.failure);
    expect(bloc.state.errorMessage, 'document_list_load_failed');
  });

  test('invalid page size is rejected at runtime', () {
    final repo = FakeDocumentListRepository(
      (query) async => DocumentListPage(
        items: const [],
        totalCount: 0,
        offset: query.offset,
        limit: query.limit,
      ),
    );

    expect(
      () => DocumentListBloc(repository: repo, pageSize: 0),
      throwsArgumentError,
    );
  });
}

Future<DocumentListPage> repoCall(
  DocumentListQuery query, {
  required Completer<DocumentListPage> first,
  required Completer<DocumentListPage> second,
}) {
  return query.filters.search == null ? first.future : second.future;
}

Future<void> waitFor(
  DocumentListBloc bloc,
  bool Function(DocumentListState state) predicate,
) async {
  if (predicate(bloc.state)) return;
  await bloc.stream.firstWhere(predicate).timeout(const Duration(seconds: 3));
}

Future<void> waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class FakeDocumentListRepository implements DocumentListRepository {
  FakeDocumentListRepository(this.handler);

  final Future<DocumentListPage> Function(DocumentListQuery query) handler;
  final List<DocumentListQuery> queries = [];

  @override
  Future<DocumentListPage> getDocuments(DocumentListQuery query) {
    queries.add(query);
    return handler(query);
  }

  @override
  Future<List<DocumentSourceFileItem>> getSourceFiles(int documentId) async =>
      const [];

  @override
  Future<void> setPreferredSourceFile(int documentId, int fileId) async {}
}
