// test/features/duplicates/duplicate_review_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/features/duplicates/domain/entities/duplicate_group_details.dart';
import 'package:legal_library_manager/features/duplicates/domain/entities/duplicate_group_file_item.dart';
import 'package:legal_library_manager/features/duplicates/domain/entities/duplicate_group_summary.dart';
import 'package:legal_library_manager/features/duplicates/domain/repositories/duplicate_review_repository.dart';
import 'package:legal_library_manager/features/duplicates/presentation/bloc/duplicate_review_bloc.dart';
import 'package:legal_library_manager/features/duplicates/presentation/bloc/duplicate_review_event.dart';
import 'package:legal_library_manager/features/duplicates/presentation/bloc/duplicate_review_state.dart';

// â”€â”€ Fake repository â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _FakeRepository implements DuplicateReviewRepository {
  _FakeRepository({
    this.groupsResult,
    this.detailsResult,
    this.throwOnGroups = false,
    this.throwOnDetails = false,
  });

  final DuplicateGroupPage? groupsResult;
  final DuplicateGroupDetails? detailsResult;
  final bool throwOnGroups;
  final bool throwOnDetails;

  int groupCallCount = 0;
  int detailCallCount = 0;
  int preferredCallCount = 0;
  int hiddenCallCount = 0;
  int reviewCallCount = 0;

  @override
  Future<DuplicateGroupPage> getGroups({int offset = 0, int limit = 50}) async {
    groupCallCount++;
    if (throwOnGroups) throw Exception('groups error');
    return groupsResult ??
        const DuplicateGroupPage(
          groups: [],
          totalCount: 0,
          pendingReviewCount: 0,
          offset: 0,
          limit: 50,
        );
  }

  @override
  Future<DuplicateGroupDetails> getGroupDetails(int groupId) async {
    detailCallCount++;
    if (throwOnDetails) throw Exception('details error');
    return detailsResult ?? _makeFakeDetails(groupId);
  }

  @override
  Future<void> setPreferredMember({
    required int groupId,
    required int fileId,
  }) async {
    preferredCallCount++;
  }

  @override
  Future<void> setMemberHidden({
    required int groupId,
    required int fileId,
    required bool hidden,
  }) async {
    hiddenCallCount++;
  }

  @override
  Future<void> updateReview({
    required int groupId,
    required String statusKey,
    String? notes,
  }) async {
    reviewCallCount++;
  }
}

DuplicateGroupSummary _makeSummary({int id = 1, int memberCount = 2}) =>
    DuplicateGroupSummary(
      id: id,
      groupCode: 'GRP-$id',
      sha256Hash: 'a' * 64,
      reviewStatusKey: 'unreviewed',
      memberCount: memberCount,
      createdAt: '2026-06-20T10:00:00.000Z',
      updatedAt: '2026-06-20T10:00:00.000Z',
    );

DuplicateGroupFileItem _makeMember({int fileId = 10, bool preferred = false}) =>
    DuplicateGroupFileItem(
      fileId: fileId,
      documentId: 1,
      fileName: 'file-$fileId.pdf',
      absolutePath: '/tmp/file-$fileId.pdf',
      fileRoleKey: FileRoleKey.sourceOriginal,
      fileHealthKey: FileHealthKey.healthy,
      fileSizeBytes: 1024,
      workflowStatusKey: WorkflowStatusKey.imported,
      isHiddenFromSearch: false,
      isPreferred: preferred,
      addedAt: '2026-06-20T10:00:00.000Z',
    );

DuplicateGroupDetails _makeFakeDetails(int groupId) => DuplicateGroupDetails(
  summary: _makeSummary(id: groupId),
  members: [_makeMember(), _makeMember(fileId: 11)],
);

// â”€â”€ Tests â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

void main() {
  group('DuplicateReviewBloc', () {
    late DuplicateReviewBloc bloc;

    tearDown(() => bloc.close());

    test('initial state has initial list status and no selection', () {
      bloc = DuplicateReviewBloc(repository: _FakeRepository());
      expect(bloc.state.listStatus, DuplicateListStatus.initial);
      expect(bloc.state.groups, isEmpty);
      expect(bloc.state.selectedGroupId, isNull);
    });

    test('rejects invalid pageSize', () {
      expect(
        () => DuplicateReviewBloc(repository: _FakeRepository(), pageSize: 0),
        throwsArgumentError,
      );
    });

    test('DuplicateReviewStarted loads groups on initial state', () async {
      final summary = _makeSummary();
      final repo = _FakeRepository(
        groupsResult: DuplicateGroupPage(
          groups: [summary],
          totalCount: 1,
          pendingReviewCount: 1,
          offset: 0,
          limit: 50,
        ),
      );
      bloc = DuplicateReviewBloc(repository: repo);

      bloc.add(const DuplicateReviewStarted());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.listStatus, DuplicateListStatus.success);
      expect(bloc.state.groups.length, 1);
      expect(bloc.state.totalCount, 1);
      expect(bloc.state.pendingReviewCount, 1);
    });

    test('DuplicateReviewStarted is ignored if not in initial state', () async {
      final repo = _FakeRepository();
      bloc = DuplicateReviewBloc(repository: repo);

      bloc.add(const DuplicateReviewStarted());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final firstCallCount = repo.groupCallCount;

      bloc.add(const DuplicateReviewStarted());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.groupCallCount, firstCallCount); // no extra call
    });

    test('failure state is emitted when repository throws', () async {
      bloc = DuplicateReviewBloc(
        repository: _FakeRepository(throwOnGroups: true),
      );

      bloc.add(const DuplicateReviewStarted());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.listStatus, DuplicateListStatus.failure);
      expect(bloc.state.listError, isNotNull);
    });

    test('DuplicateReviewRefreshed reloads from scratch', () async {
      final repo = _FakeRepository();
      bloc = DuplicateReviewBloc(repository: repo);

      bloc.add(const DuplicateReviewRefreshed());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      bloc.add(const DuplicateReviewRefreshed());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.groupCallCount, 2);
    });

    test('DuplicateReviewGroupSelected loads detail for the group', () async {
      final details = _makeFakeDetails(5);
      bloc = DuplicateReviewBloc(
        repository: _FakeRepository(detailsResult: details),
      );

      bloc.add(const DuplicateReviewGroupSelected(5));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.selectedGroupId, 5);
      expect(bloc.state.detailStatus, DuplicateDetailStatus.success);
      expect(bloc.state.selectedDetails?.summary.id, 5);
    });

    test(
      'selecting same group a second time is a no-op when already loaded',
      () async {
        final repo = _FakeRepository();
        bloc = DuplicateReviewBloc(repository: repo);

        bloc.add(const DuplicateReviewGroupSelected(1));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final firstDetailCount = repo.detailCallCount;

        bloc.add(const DuplicateReviewGroupSelected(1));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(repo.detailCallCount, firstDetailCount);
      },
    );

    test('detail failure state is set when detail load throws', () async {
      bloc = DuplicateReviewBloc(
        repository: _FakeRepository(throwOnDetails: true),
      );

      bloc.add(const DuplicateReviewGroupSelected(1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.detailStatus, DuplicateDetailStatus.failure);
      expect(bloc.state.selectedDetails, isNull);
    });

    test(
      'DuplicateReviewNextPageRequested is ignored when not in success state',
      () async {
        final repo = _FakeRepository();
        bloc = DuplicateReviewBloc(repository: repo);

        // In initial state â€” should be ignored.
        bloc.add(const DuplicateReviewNextPageRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(repo.groupCallCount, 0);
      },
    );

    test(
      'DuplicateReviewNextPageRequested is ignored when hasMore is false',
      () async {
        final repo = _FakeRepository(
          groupsResult: const DuplicateGroupPage(
            groups: [],
            totalCount: 0,
            pendingReviewCount: 0,
            offset: 0,
            limit: 50,
          ),
        );
        bloc = DuplicateReviewBloc(repository: repo);
        bloc.add(const DuplicateReviewStarted());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        bloc.add(const DuplicateReviewNextPageRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(repo.groupCallCount, 1); // only the initial load
      },
    );

    test('stale list responses are discarded', () async {
      // After a refresh, _listVersion is 1. A version-0 internal event is stale
      // and must be ignored while the real version-1 response still applies.
      final summary = _makeSummary();
      final repo = _FakeRepository(
        groupsResult: DuplicateGroupPage(
          groups: [summary],
          totalCount: 1,
          pendingReviewCount: 1,
          offset: 0,
          limit: 50,
        ),
      );
      bloc = DuplicateReviewBloc(repository: repo);

      // Refresh bumps _listVersion to 1; immediately inject stale version-0.
      bloc.add(const DuplicateReviewRefreshed());
      bloc.add(
        const DuplicateReviewPageLoaded(
          0, // version 0 â€” stale once _listVersion == 1
          DuplicateGroupPage(
            groups: [],
            totalCount: 0,
            pendingReviewCount: 0,
            offset: 0,
            limit: 50,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Stale response was discarded; real version-1 response from repo applied.
      expect(bloc.state.listStatus, DuplicateListStatus.success);
      expect(bloc.state.groups.length, 1);
    });

    test(
      'setting preferred file writes then refreshes details and list',
      () async {
        final repo = _FakeRepository(
          groupsResult: DuplicateGroupPage(
            groups: [_makeSummary()],
            totalCount: 1,
            pendingReviewCount: 1,
            offset: 0,
            limit: 50,
          ),
          detailsResult: _makeFakeDetails(1),
        );
        bloc = DuplicateReviewBloc(repository: repo);

        bloc.add(
          const DuplicateReviewPreferredMemberSet(groupId: 1, fileId: 10),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(repo.preferredCallCount, 1);
        expect(repo.detailCallCount, 1);
        expect(repo.groupCallCount, 1);
        expect(bloc.state.operation, DuplicateReviewOperation.none);
        expect(bloc.state.messageKey, 'duplicate_preferred_saved');
      },
    );

    test('hidden toggle writes then refreshes details and list', () async {
      final repo = _FakeRepository(
        groupsResult: DuplicateGroupPage(
          groups: [_makeSummary()],
          totalCount: 1,
          pendingReviewCount: 1,
          offset: 0,
          limit: 50,
        ),
        detailsResult: _makeFakeDetails(1),
      );
      bloc = DuplicateReviewBloc(repository: repo);

      bloc.add(
        const DuplicateReviewMemberHiddenSet(
          groupId: 1,
          fileId: 10,
          hidden: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.hiddenCallCount, 1);
      expect(bloc.state.messageKey, 'duplicate_member_hidden');
    });

    test('review save writes then refreshes details and list', () async {
      final repo = _FakeRepository(
        groupsResult: DuplicateGroupPage(
          groups: [_makeSummary()],
          totalCount: 1,
          pendingReviewCount: 1,
          offset: 0,
          limit: 50,
        ),
        detailsResult: _makeFakeDetails(1),
      );
      bloc = DuplicateReviewBloc(repository: repo);

      bloc.add(
        const DuplicateReviewGroupReviewSaved(
          groupId: 1,
          statusKey: 'reviewed',
          notes: 'checked',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.reviewCallCount, 1);
      expect(bloc.state.messageKey, 'duplicate_review_saved');
    });
  });
}
