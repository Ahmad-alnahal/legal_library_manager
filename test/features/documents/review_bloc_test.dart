import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/core/validation/validation_error.dart';
import 'package:legal_library_manager/core/validation/validation_result.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_aggregate.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_common_metadata.dart';
import 'package:legal_library_manager/features/documents/domain/entities/draft_save_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/review_queue_item.dart';
import 'package:legal_library_manager/features/documents/domain/entities/review_queue_query.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_metadata_repository.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/review_queue_repository.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/approve_classification.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/load_document_aggregate.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/return_to_in_progress.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/save_document_draft.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/validate_classification.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/review_bloc.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/review_event.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/review_state.dart';
import 'package:legal_library_manager/features/reference/domain/repositories/reference_repository.dart';

void main() {
  const now = '2026-06-09T12:00:00.000Z';

  DocumentAggregate makeAgg(
    int id, {
    String status = WorkflowStatusKey.inProgress,
    String? title = 'عنوان',
    String? fileName,
  }) => DocumentAggregate(
    documentId: id,
    workflowStatusKey: status,
    common: DocumentCommonMetadata(title: title),
    details: null,
    primaryClassification: null,
    additionalClassifications: const [],
    keywords: const [],
    files: const [],
    conversions: const [],
    preferredSourceFileName: fileName,
  );

  ReviewQueueItem qItem(int id) =>
      ReviewQueueItem(
        id: id,
        workflowStatusKey: WorkflowStatusKey.imported,
        updatedAt: now,
      );

  ReviewQueuePage qPage(List<int> ids, int total, {int offset = 0}) =>
      ReviewQueuePage(
        items: ids.map(qItem).toList(),
        totalCount: total,
        offset: offset,
        limit: 50,
      );

  ReviewBloc build({
    required FakeReviewQueueRepository queue,
    FakeLoad? load,
    FakeSave? save,
    FakeApprove? approve,
    FakeReturn? ret,
    int pageSize = 50,
  }) => ReviewBloc(
    queueRepository: queue,
    loadDocument: load ?? FakeLoad(),
    saveDraft: save ?? FakeSave(),
    approveClassification: approve ?? FakeApprove(),
    returnToInProgress: ret ?? FakeReturn(),
    pageSize: pageSize,
  );

  test('loads the initial queue, then a selected document', () async {
    final queue = FakeReviewQueueRepository((q) async => qPage([1, 2, 3], 3));
    final load = FakeLoad()..handler = (id) async => makeAgg(id);
    final bloc = build(queue: queue, load: load);
    addTearDown(bloc.close);

    bloc.add(const ReviewStarted());
    await waitFor(bloc, (s) => s.queueStatus == ReviewQueueStatus.success);
    expect(bloc.state.queueItems.map((e) => e.id), [1, 2, 3]);

    bloc.add(const ReviewDocumentSelected(2));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
    expect(bloc.state.selectedDocumentId, 2);
    expect(bloc.state.aggregate!.documentId, 2);
    expect(bloc.state.draft, isNotNull);
    expect(bloc.state.isDirty, isFalse);
  });

  test('loads the next queue page', () async {
    final queue = FakeReviewQueueRepository(
      (q) async => q.offset == 0 ? qPage([1, 2], 4) : qPage([3, 4], 4),
    );
    final bloc = build(queue: queue, pageSize: 2);
    addTearDown(bloc.close);

    bloc.add(const ReviewStarted());
    await waitFor(bloc, (s) => s.queueStatus == ReviewQueueStatus.success);
    expect(bloc.state.hasMoreQueue, isTrue);

    bloc.add(const ReviewNextPageRequested());
    await waitFor(bloc, (s) => s.queueItems.length == 4);
    expect(bloc.state.queueItems.map((e) => e.id), [1, 2, 3, 4]);
    expect(bloc.state.hasMoreQueue, isFalse);
  });

  test('tracks unsaved edits as dirty', () async {
    final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
    final load = FakeLoad()..handler = (id) async => makeAgg(id);
    final bloc = build(queue: queue, load: load);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(1));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
    expect(bloc.state.isDirty, isFalse);

    bloc.add(ReviewDraftEdited(edit(bloc, 'محرر')));
    await waitFor(bloc, (s) => s.isDirty);
    expect(bloc.state.isDirty, isTrue);
  });

  test(
    'selecting another document while dirty requires confirmation',
    () async {
      final queue = FakeReviewQueueRepository((q) async => qPage([1, 2], 2));
      final load = FakeLoad()..handler = (id) async => makeAgg(id);
      final bloc = build(queue: queue, load: load);
      addTearDown(bloc.close);

      bloc
        ..add(const ReviewStarted())
        ..add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );
      bloc.add(ReviewDraftEdited(edit(bloc, 'محرر')));
      await waitFor(bloc, (s) => s.isDirty);

      // A different document is NOT silently loaded.
      bloc.add(const ReviewDocumentSelected(2));
      await waitFor(bloc, (s) => s.requiresSelectionConfirmation);
      expect(bloc.state.selectedDocumentId, 1);
      expect(bloc.state.pendingSelectionId, 2);

      // Cancelling keeps the current document and edits.
      bloc.add(const ReviewSelectionChangeCancelled());
      await waitFor(bloc, (s) => !s.requiresSelectionConfirmation);
      expect(bloc.state.selectedDocumentId, 1);
      expect(bloc.state.isDirty, isTrue);

      // Confirming discards edits and loads the pending document.
      bloc
        ..add(const ReviewDocumentSelected(2))
        ..add(const ReviewSelectionChangeConfirmed());
      await waitFor(
        bloc,
        (s) =>
            s.selectedDocumentId == 2 &&
            s.documentStatus == ReviewDocumentStatus.loaded,
      );
      expect(bloc.state.isDirty, isFalse);
    },
  );

  test('a stale document load cannot overwrite a newer selection', () async {
    final c1 = Completer<DocumentAggregate?>();
    final c2 = Completer<DocumentAggregate?>();
    final queue = FakeReviewQueueRepository((q) async => qPage([1, 2], 2));
    final load = FakeLoad()..handler = (id) => id == 1 ? c1.future : c2.future;
    final bloc = build(queue: queue, load: load);
    addTearDown(bloc.close);

    bloc.add(const ReviewStarted());
    await waitFor(bloc, (s) => s.queueStatus == ReviewQueueStatus.success);

    bloc.add(const ReviewDocumentSelected(1));
    await waitFor(
      bloc,
      (s) => s.documentStatus == ReviewDocumentStatus.loading,
    );
    bloc.add(const ReviewDocumentSelected(2));
    await waitFor(bloc, (s) => s.selectedDocumentId == 2);

    c2.complete(makeAgg(2));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
    c1.complete(makeAgg(1)); // stale
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bloc.state.selectedDocumentId, 2);
    expect(bloc.state.aggregate!.documentId, 2);
  });

  test('saving a draft keeps the document selected and refreshes it', () async {
    final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
    final load = FakeLoad()
      ..handler = (id) async => makeAgg(id, title: 'محفوظ');
    final save = FakeSave()
      ..handler = (_) async => const ValidationResult.valid();
    final bloc = build(queue: queue, load: load, save: save);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(1));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
    bloc.add(ReviewDraftEdited(edit(bloc, 'محرر')));
    await waitFor(bloc, (s) => s.isDirty);

    bloc.add(const ReviewDraftSaved());
    await waitFor(
      bloc,
      (s) => !s.isDirty && s.operation == ReviewOperation.none,
    );
    expect(save.callCount, 1);
    expect(bloc.state.selectedDocumentId, 1);
    expect(bloc.state.draft!.common.title, 'محفوظ');
  });

  test('a draft validation failure surfaces errors and stays dirty', () async {
    final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
    final load = FakeLoad()..handler = (id) async => makeAgg(id);
    final save = FakeSave()
      ..handler = (_) async => ValidationResult([
        const ValidationError(
          field: 'title',
          code: 'required',
          message: 'required',
        ),
      ]);
    final bloc = build(queue: queue, load: load, save: save);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(1));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
    bloc.add(ReviewDraftEdited(edit(bloc, 'محرر')));
    await waitFor(bloc, (s) => s.isDirty);

    bloc.add(const ReviewDraftSaved());
    await waitFor(bloc, (s) => s.validationErrors.isNotEmpty);
    expect(bloc.state.validationErrors.single.field, 'title');
    expect(bloc.state.operation, ReviewOperation.none);
    expect(bloc.state.isDirty, isTrue);
  });

  test('approval auto-selects the next queue document', () async {
    var approved = false;
    final queue = FakeReviewQueueRepository(
      (q) async => approved ? qPage([2, 3], 2) : qPage([1, 2, 3], 3),
    );
    final load = FakeLoad()..handler = (id) async => makeAgg(id);
    final approve = FakeApprove()
      ..handler = (_) async {
        approved = true;
        return const ValidationResult.valid();
      };
    final bloc = build(queue: queue, load: load, approve: approve);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(1));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);

    bloc.add(const ReviewClassificationApproved());
    await waitFor(
      bloc,
      (s) =>
          s.selectedDocumentId == 2 &&
          s.documentStatus == ReviewDocumentStatus.loaded,
    );
    expect(bloc.state.queueItems.map((e) => e.id), [2, 3]);
    expect(bloc.state.operation, ReviewOperation.none);
  });

  test('approving the last document clears the selection', () async {
    var approved = false;
    final queue = FakeReviewQueueRepository(
      (q) async => approved ? qPage([1, 2], 2) : qPage([1, 2, 3], 3),
    );
    final load = FakeLoad()..handler = (id) async => makeAgg(id);
    final approve = FakeApprove()
      ..handler = (_) async {
        approved = true;
        return const ValidationResult.valid();
      };
    final bloc = build(queue: queue, load: load, approve: approve);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(3));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);

    bloc.add(const ReviewClassificationApproved());
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.none);
    expect(bloc.state.selectedDocumentId, isNull);
    expect(bloc.state.queueItems.map((e) => e.id), [1, 2]);
  });

  test(
    'approval validation failure surfaces errors, keeps selection',
    () async {
      final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
      final load = FakeLoad()..handler = (id) async => makeAgg(id);
      final approve = FakeApprove()
        ..handler = (_) async => ValidationResult([
          const ValidationError(
            field: 'book.author',
            code: 'required',
            message: 'required',
          ),
        ]);
      final bloc = build(queue: queue, load: load, approve: approve);
      addTearDown(bloc.close);

      bloc
        ..add(const ReviewStarted())
        ..add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );

      bloc.add(const ReviewClassificationApproved());
      await waitFor(bloc, (s) => s.validationErrors.isNotEmpty);
      expect(bloc.state.validationErrors.single.field, 'book.author');
      expect(bloc.state.selectedDocumentId, 1);
      expect(bloc.state.operation, ReviewOperation.none);
    },
  );

  test('explicit return to in_progress reloads the document', () async {
    var returned = false;
    final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
    final load = FakeLoad()
      ..handler = (id) async => makeAgg(
        id,
        status: returned
            ? WorkflowStatusKey.inProgress
            : WorkflowStatusKey.classified,
      );
    final ret = FakeReturn()
      ..handler = (_) async {
        returned = true;
        return const ValidationResult.valid();
      };
    final bloc = build(queue: queue, load: load, ret: ret);
    addTearDown(bloc.close);

    bloc.add(const ReviewQueueScopeChanged(ReviewQueueScope.classified));
    await waitFor(bloc, (s) => s.scope == ReviewQueueScope.classified);
    bloc.add(const ReviewDocumentSelected(1));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
    expect(bloc.state.aggregate!.workflowStatusKey, WorkflowStatusKey.classified);

    bloc.add(const ReviewReturnedToInProgress());
    await waitFor(
      bloc,
      (s) => s.aggregate?.workflowStatusKey == WorkflowStatusKey.inProgress,
    );
    expect(ret.callCount, 1);
    expect(bloc.state.selectedDocumentId, 1);
    expect(bloc.state.documentStatus, ReviewDocumentStatus.loaded);
  });

  test(
    'refresh syncs the selected queue tile workflow from loaded aggregate',
    () async {
      var copied = false;
      final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
      final load = FakeLoad()
        ..handler = (id) async => makeAgg(
          id,
          status: copied
              ? WorkflowStatusKey.copiedToLibrary
              : WorkflowStatusKey.classified,
        );
      final bloc = build(queue: queue, load: load);
      addTearDown(bloc.close);

      bloc.add(const ReviewQueueScopeChanged(ReviewQueueScope.classified));
      await waitFor(bloc, (s) => s.scope == ReviewQueueScope.classified);
      bloc.add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );
      expect(
        bloc.state.queueItems.single.workflowStatusKey,
        WorkflowStatusKey.classified,
      );

      copied = true;
      bloc.add(const ReviewRefreshRequested());
      await waitFor(
        bloc,
        (s) =>
            s.aggregate?.workflowStatusKey ==
            WorkflowStatusKey.copiedToLibrary,
      );

      expect(
        bloc.state.queueItems.single.workflowStatusKey,
        WorkflowStatusKey.copiedToLibrary,
      );
    },
  );

  test('return is rejected for a non-classified document', () async {
    final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
    final load = FakeLoad()..handler = (id) async => makeAgg(id);
    final ret = FakeReturn()
      ..handler = (_) async => ValidationResult([
        const ValidationError(
          field: 'workflowStatus',
          code: 'invalid_status',
          message: 'invalid',
        ),
      ]);
    final bloc = build(queue: queue, load: load, ret: ret);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(1));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);

    bloc.add(const ReviewReturnedToInProgress());
    await waitFor(bloc, (s) => s.validationErrors.isNotEmpty);
    expect(bloc.state.validationErrors.single.code, 'invalid_status');
    expect(bloc.state.operation, ReviewOperation.none);
  });

  test('overlapping operations are prevented', () async {
    final completer = Completer<ValidationResult>();
    final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
    final load = FakeLoad()..handler = (id) async => makeAgg(id);
    final save = FakeSave()..handler = (_) => completer.future;
    final approve = FakeApprove();
    final bloc = build(queue: queue, load: load, save: save, approve: approve);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(1));
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
    bloc.add(ReviewDraftEdited(edit(bloc, 'محرر')));
    await waitFor(bloc, (s) => s.isDirty);

    bloc.add(const ReviewDraftSaved());
    await waitFor(bloc, (s) => s.operation == ReviewOperation.saving);
    bloc.add(const ReviewClassificationApproved()); // must be ignored
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(approve.callCount, 0);
    expect(bloc.state.operation, ReviewOperation.saving);

    completer.complete(const ValidationResult.valid());
    await waitFor(bloc, (s) => s.operation == ReviewOperation.none);
  });

  test('queue and document load failures expose safe error keys', () async {
    var failQueue = true;
    final queue = FakeReviewQueueRepository((q) async {
      if (failQueue) throw StateError('boom');
      return qPage([1], 1);
    });
    var failLoad = true;
    final load = FakeLoad()
      ..handler = (id) async {
        if (failLoad) throw StateError('boom');
        return makeAgg(id);
      };
    final bloc = build(queue: queue, load: load);
    addTearDown(bloc.close);

    bloc.add(const ReviewStarted());
    await waitFor(bloc, (s) => s.queueStatus == ReviewQueueStatus.failure);
    expect(bloc.state.queueErrorKey, 'review_queue_load_failed');

    failQueue = false;
    bloc.add(const ReviewRetryRequested());
    await waitFor(bloc, (s) => s.queueStatus == ReviewQueueStatus.success);

    bloc.add(const ReviewDocumentSelected(1));
    await waitFor(
      bloc,
      (s) => s.documentStatus == ReviewDocumentStatus.failure,
    );
    expect(bloc.state.documentErrorKey, 'review_document_load_failed');

    failLoad = false;
    bloc.add(const ReviewRetryRequested());
    await waitFor(bloc, (s) => s.documentStatus == ReviewDocumentStatus.loaded);
  });

  test('a missing document yields a not-found state', () async {
    final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
    final load = FakeLoad()..handler = (_) async => null;
    final bloc = build(queue: queue, load: load);
    addTearDown(bloc.close);

    bloc
      ..add(const ReviewStarted())
      ..add(const ReviewDocumentSelected(1));
    await waitFor(
      bloc,
      (s) => s.documentStatus == ReviewDocumentStatus.notFound,
    );
    expect(bloc.state.aggregate, isNull);
  });

  group('filename title suggestion', () {
    test(
      'an untitled document is suggested a title without the final extension',
      () async {
        final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
        final load = FakeLoad()
          ..handler = (id) async =>
              makeAgg(id, title: null, fileName: 'constitutional_law.pdf');
        final bloc = build(queue: queue, load: load);
        addTearDown(bloc.close);

        bloc
          ..add(const ReviewStarted())
          ..add(const ReviewDocumentSelected(1));
        await waitFor(
          bloc,
          (s) => s.documentStatus == ReviewDocumentStatus.loaded,
        );

        expect(bloc.state.draft!.common.title, 'constitutional_law');
        // The suggestion is an unsaved in-memory edit.
        expect(bloc.state.isDirty, isTrue);
        // The persisted baseline still has no title.
        expect(bloc.state.baselineDraft!.common.title, isNull);
      },
    );

    test('only the final extension is removed', () async {
      final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
      final load = FakeLoad()
        ..handler = (id) async =>
            makeAgg(id, title: null, fileName: 'book.final.pdf');
      final bloc = build(queue: queue, load: load);
      addTearDown(bloc.close);

      bloc
        ..add(const ReviewStarted())
        ..add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );

      expect(bloc.state.draft!.common.title, 'book.final');
    });

    test('Unicode/Arabic filenames are preserved', () async {
      final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
      final load = FakeLoad()
        ..handler = (id) async =>
            makeAgg(id, title: null, fileName: 'قانون العقوبات.pdf');
      final bloc = build(queue: queue, load: load);
      addTearDown(bloc.close);

      bloc
        ..add(const ReviewStarted())
        ..add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );

      expect(bloc.state.draft!.common.title, 'قانون العقوبات');
    });

    test('an existing non-empty title is preserved', () async {
      final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
      final load = FakeLoad()
        ..handler = (id) async =>
            makeAgg(id, title: 'عنوان مخصص', fileName: 'whatever.pdf');
      final bloc = build(queue: queue, load: load);
      addTearDown(bloc.close);

      bloc
        ..add(const ReviewStarted())
        ..add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );

      expect(bloc.state.draft!.common.title, 'عنوان مخصص');
      expect(bloc.state.isDirty, isFalse);
    });

    test('no usable filename leaves the title empty', () async {
      final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
      final load = FakeLoad()..handler = (id) async => makeAgg(id, title: null);
      final bloc = build(queue: queue, load: load);
      addTearDown(bloc.close);

      bloc
        ..add(const ReviewStarted())
        ..add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );

      expect(bloc.state.draft!.common.title, isNull);
      expect(bloc.state.isDirty, isFalse);
    });

    test('the suggested title is not persisted automatically', () async {
      final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
      final load = FakeLoad()
        ..handler = (id) async =>
            makeAgg(id, title: null, fileName: 'report.pdf');
      final save = FakeSave();
      final bloc = build(queue: queue, load: load, save: save);
      addTearDown(bloc.close);

      bloc
        ..add(const ReviewStarted())
        ..add(const ReviewDocumentSelected(1));
      await waitFor(
        bloc,
        (s) => s.documentStatus == ReviewDocumentStatus.loaded,
      );

      // Selecting alone must never trigger a save.
      expect(save.callCount, 0);
      expect(bloc.state.isDirty, isTrue);
    });

    test(
      'a cleared title is not re-suggested when the document reloads',
      () async {
        var savedEmpty = false;
        final queue = FakeReviewQueueRepository((q) async => qPage([1], 1));
        final load = FakeLoad()
          ..handler = (id) async => makeAgg(
            id,
            // After the user clears + saves, the reloaded aggregate has no
            // title; the suggestion must NOT come back.
            title: savedEmpty ? null : null,
            fileName: 'report.pdf',
          );
        final save = FakeSave()
          ..handler = (_) async {
            savedEmpty = true;
            return const ValidationResult.valid();
          };
        final bloc = build(queue: queue, load: load, save: save);
        addTearDown(bloc.close);

        bloc
          ..add(const ReviewStarted())
          ..add(const ReviewDocumentSelected(1));
        await waitFor(
          bloc,
          (s) => s.documentStatus == ReviewDocumentStatus.loaded,
        );
        expect(bloc.state.draft!.common.title, 'report');

        // User clears the suggested title, then saves.
        bloc.add(
          ReviewDraftEdited(
            bloc.state.draft!.copyWith(common: const DocumentCommonMetadata()),
          ),
        );
        await waitFor(bloc, (s) => s.draft!.common.title == null);
        bloc.add(const ReviewDraftSaved());
        await waitFor(
          bloc,
          (s) => !s.isDirty && s.operation == ReviewOperation.none,
        );

        // The reload after save must keep the title empty (no re-suggestion).
        expect(bloc.state.draft!.common.title, isNull);
        expect(bloc.state.isDirty, isFalse);
      },
    );
  });

  test('invalid page size is rejected at runtime', () {
    final queue = FakeReviewQueueRepository((q) async => qPage(const [], 0));
    expect(() => build(queue: queue, pageSize: 0), throwsArgumentError);
  });
}

/// Builds an edited draft from the current loaded draft with a new title.
DraftSaveInput edit(ReviewBloc bloc, String title) {
  final draft = bloc.state.draft!;
  return draft.copyWith(common: draft.common.copyWith(title: title));
}

Future<void> waitFor(
  ReviewBloc bloc,
  bool Function(ReviewState state) predicate,
) async {
  if (predicate(bloc.state)) return;
  await bloc.stream.firstWhere(predicate).timeout(const Duration(seconds: 3));
}

// --- test doubles ---

class _ZeroClock extends Clock {
  const _ZeroClock();
  @override
  DateTime nowUtc() => DateTime.utc(2026);
}

/// A repository stub that must never actually be invoked: the use-case test
/// doubles override `call` and ignore the injected repositories.
class _Never implements DocumentMetadataRepository, ReferenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('repository should not be called in this test');
}

class FakeReviewQueueRepository implements ReviewQueueRepository {
  FakeReviewQueueRepository(this.handler);

  final Future<ReviewQueuePage> Function(ReviewQueueQuery query) handler;
  final List<ReviewQueueQuery> queries = [];

  @override
  Future<ReviewQueuePage> getQueue(ReviewQueueQuery query) {
    queries.add(query);
    return handler(query);
  }
}

class FakeLoad extends LoadDocumentAggregate {
  FakeLoad() : super(_Never());

  Future<DocumentAggregate?> Function(int id) handler = (_) async => null;
  int callCount = 0;

  @override
  Future<DocumentAggregate?> call(int documentId) {
    callCount++;
    return handler(documentId);
  }
}

class FakeSave extends SaveDocumentDraft {
  FakeSave()
    : super(
        repository: _Never(),
        references: _Never(),
        classificationValidator: ValidateClassification(
          references: _Never(),
          clock: const _ZeroClock(),
        ),
        clock: const _ZeroClock(),
      );

  Future<ValidationResult> Function(DraftSaveInput input) handler = (_) async =>
      const ValidationResult.valid();
  int callCount = 0;

  @override
  Future<ValidationResult> call(DraftSaveInput input) {
    callCount++;
    return handler(input);
  }
}

class FakeApprove extends ApproveClassification {
  FakeApprove()
    : super(
        repository: _Never(),
        validator: ValidateClassification(
          references: _Never(),
          clock: const _ZeroClock(),
        ),
        clock: const _ZeroClock(),
      );

  Future<ValidationResult> Function(int id) handler = (_) async =>
      const ValidationResult.valid();
  int callCount = 0;

  @override
  Future<ValidationResult> call(int documentId) {
    callCount++;
    return handler(documentId);
  }
}

class FakeReturn extends ReturnToInProgress {
  FakeReturn() : super(repository: _Never(), clock: const _ZeroClock());

  Future<ValidationResult> Function(int id) handler = (_) async =>
      const ValidationResult.valid();
  int callCount = 0;

  @override
  Future<ValidationResult> call(int documentId) {
    callCount++;
    return handler(documentId);
  }
}
