// test/features/related_files/related_review_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/related_files/application/load_pending_candidates_use_case.dart';
import 'package:legal_library_manager/features/related_files/application/update_candidate_status_use_case.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/related_file_review_row.dart';
import 'package:legal_library_manager/features/related_files/presentation/bloc/related_review_bloc.dart';

import 'support/related_file_fakes.dart';

RelatedReviewBloc _buildBloc(FakeRelatedFileCandidateRepository repo) =>
    RelatedReviewBloc(
      loadCandidates: LoadPendingCandidatesUseCase(repo),
      updateStatus: UpdateCandidateStatusUseCase(repo, const SystemClock()),
    );

void main() {
  // ── Test 1 ────────────────────────────────────────────────────────────────
  test('initial state has status initial and empty rows', () {
    final repo = FakeRelatedFileCandidateRepository();
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);
    // State at construction before the async initial load completes
    expect(bloc.state.status, RelatedReviewStatus.initial);
    expect(bloc.state.rows, isEmpty);
    expect(bloc.state.actionError, isFalse);
  });

  // ── Test 2 ────────────────────────────────────────────────────────────────
  test('emits loaded with rows when repository returns data', () async {
    final rows = [fakeReviewRow(1), fakeReviewRow(2)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == RelatedReviewStatus.loaded);
    expect(bloc.state.rows, hasLength(2));
    expect(bloc.state.actionError, isFalse);
  });

  // ── Test 3 ────────────────────────────────────────────────────────────────
  test('emits failure when repository throws on load', () async {
    final failRepo = _ThrowingLoadRepo();
    final bloc = RelatedReviewBloc(
      loadCandidates: LoadPendingCandidatesUseCase(failRepo),
      updateStatus: UpdateCandidateStatusUseCase(failRepo, const SystemClock()),
    );
    addTearDown(bloc.close);

    await bloc.stream.firstWhere(
      (s) => s.status == RelatedReviewStatus.failure,
    );
    expect(bloc.state.rows, isEmpty);
  });

  // ── Test 4 ────────────────────────────────────────────────────────────────
  test('confirm removes the row from state optimistically', () async {
    final rows = [fakeReviewRow(1), fakeReviewRow(2)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == RelatedReviewStatus.loaded);
    bloc.add(const RelatedReviewConfirmRequested(candidateId: 1));

    await bloc.stream.firstWhere((s) => s.rows.length == 1);
    expect(bloc.state.rows.first.candidateId, 2);
    expect(bloc.state.actionError, isFalse);
  });

  // ── Test 5 ────────────────────────────────────────────────────────────────
  test('reject removes the row from state optimistically', () async {
    final rows = [fakeReviewRow(5)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == RelatedReviewStatus.loaded);
    bloc.add(const RelatedReviewRejectRequested(candidateId: 5));

    await bloc.stream.firstWhere((s) => s.rows.isEmpty);
    expect(bloc.state.actionError, isFalse);
  });

  // ── Test 6 ────────────────────────────────────────────────────────────────
  test('dismiss removes the row from state optimistically', () async {
    final rows = [fakeReviewRow(7)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == RelatedReviewStatus.loaded);
    bloc.add(const RelatedReviewDismissRequested(candidateId: 7));

    await bloc.stream.firstWhere((s) => s.rows.isEmpty);
    expect(bloc.state.actionError, isFalse);
  });

  // ── Test 7 ────────────────────────────────────────────────────────────────
  test('action failure sets actionError without clearing rows', () async {
    final rows = [fakeReviewRow(3)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows)
      ..failUpdateStatus = true;
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == RelatedReviewStatus.loaded);
    bloc.add(const RelatedReviewConfirmRequested(candidateId: 3));

    await bloc.stream.firstWhere((s) => s.actionError);
    expect(bloc.state.rows, hasLength(1)); // row still present
  });

  // ── Test 8 ────────────────────────────────────────────────────────────────
  test('reload after action error clears actionError', () async {
    final rows = [fakeReviewRow(9)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows)
      ..failUpdateStatus = true;
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await bloc.stream.firstWhere((s) => s.status == RelatedReviewStatus.loaded);
    bloc.add(const RelatedReviewConfirmRequested(candidateId: 9));
    await bloc.stream.firstWhere((s) => s.actionError);

    // Fix the error condition and reload
    repo.failUpdateStatus = false;
    bloc.add(const RelatedReviewLoadRequested());
    await bloc.stream.firstWhere((s) => s.status == RelatedReviewStatus.loaded);
    expect(bloc.state.actionError, isFalse);
  });
}

// Helper fake that always throws on listPendingForReview
class _ThrowingLoadRepo extends FakeRelatedFileCandidateRepository {
  @override
  Future<List<RelatedFileReviewRow>> listPendingForReview({
    int limit = 50,
  }) async {
    throw StateError('load failed (test)');
  }
}
