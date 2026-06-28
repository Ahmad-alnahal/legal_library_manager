// test/features/related_files/related_review_section_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show
        GlobalMaterialLocalizations,
        GlobalWidgetsLocalizations,
        GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/related_files/application/load_pending_candidates_use_case.dart';
import 'package:legal_library_manager/features/related_files/application/update_candidate_status_use_case.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/related_file_review_row.dart';
import 'package:legal_library_manager/features/related_files/presentation/bloc/related_review_bloc.dart';
import 'package:legal_library_manager/features/related_files/presentation/widgets/related_review_section.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

import 'support/related_file_fakes.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps [child] with Material, RTL locale, and l10n.
/// Uses BlocProvider.value — NOT .create — to avoid the Windows hang bug.
Widget _wrap(Widget child, RelatedReviewBloc bloc) {
  return MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ar')],
    home: Scaffold(
      body: BlocProvider<RelatedReviewBloc>.value(value: bloc, child: child),
    ),
  );
}

RelatedReviewBloc _buildBloc(FakeRelatedFileCandidateRepository repo) =>
    RelatedReviewBloc(
      loadCandidates: LoadPendingCandidatesUseCase(repo),
      updateStatus: UpdateCandidateStatusUseCase(repo, const SystemClock()),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Test 1 ────────────────────────────────────────────────────────────────
  testWidgets('shows loading indicator while loading', (tester) async {
    final completer = Completer<List<RelatedFileReviewRow>>();
    final repo = _ControllableRepo(completer);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(_wrap(const RelatedReviewSection(), bloc));
    await tester.pump(); // process the BLoC load event (bloc → loading state)
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Complete the future so fakeAsync can drain cleanly.
    completer.complete([]);
    await tester.pumpAndSettle();
  });

  // ── Test 2 ────────────────────────────────────────────────────────────────
  testWidgets('shows empty state when no pending rows', (tester) async {
    final repo = FakeRelatedFileCandidateRepository();
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(_wrap(const RelatedReviewSection(), bloc));
    await tester.pumpAndSettle();

    expect(
      find.text('لا توجد ملفات مقترحة للمراجعة في الوقت الحالي.'),
      findsOneWidget,
    );
  });

  // ── Test 3 ────────────────────────────────────────────────────────────────
  testWidgets('shows candidate card when rows are loaded', (tester) async {
    final rows = [fakeReviewRow(1)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(_wrap(const RelatedReviewSection(), bloc));
    await tester.pumpAndSettle();

    expect(find.text('file_a_1.pdf'), findsOneWidget);
    expect(find.text('file_b_1.doc'), findsOneWidget);
  });

  // ── Test 4 ────────────────────────────────────────────────────────────────
  testWidgets('tapping confirm removes the card', (tester) async {
    final rows = [fakeReviewRow(10)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(_wrap(const RelatedReviewSection(), bloc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تأكيد الترابط'));
    await tester.pumpAndSettle();

    expect(find.text('file_a_10.pdf'), findsNothing);
  });

  // ── Test 5 ────────────────────────────────────────────────────────────────
  testWidgets('tapping reject removes the card', (tester) async {
    final rows = [fakeReviewRow(11)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(_wrap(const RelatedReviewSection(), bloc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('رفض'));
    await tester.pumpAndSettle();

    expect(find.text('file_a_11.pdf'), findsNothing);
  });

  // ── Test 6 ────────────────────────────────────────────────────────────────
  testWidgets('tapping dismiss removes the card', (tester) async {
    final rows = [fakeReviewRow(12)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows);
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(_wrap(const RelatedReviewSection(), bloc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تجاهل'));
    await tester.pumpAndSettle();

    expect(find.text('file_a_12.pdf'), findsNothing);
  });

  // ── Test 7 ────────────────────────────────────────────────────────────────
  testWidgets('action error shows a snackbar', (tester) async {
    final rows = [fakeReviewRow(20)];
    final repo = FakeRelatedFileCandidateRepository(rows: rows)
      ..failUpdateStatus = true;
    final bloc = _buildBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(_wrap(const RelatedReviewSection(), bloc));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تأكيد الترابط'));
    await tester.pumpAndSettle();

    expect(
      find.text('حدث خطأ أثناء معالجة الإجراء. حاول مرة أخرى.'),
      findsOneWidget,
    );
  });
}

/// A repo that delegates listPendingForReview to an externally controlled
/// Completer — used to hold the bloc in the loading state for test 1.
class _ControllableRepo extends FakeRelatedFileCandidateRepository {
  _ControllableRepo(this._completer);
  final Completer<List<RelatedFileReviewRow>> _completer;

  @override
  Future<List<RelatedFileReviewRow>> listPendingForReview({int limit = 50}) =>
      _completer.future;
}
