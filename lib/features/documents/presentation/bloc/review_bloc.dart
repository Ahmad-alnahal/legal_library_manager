import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/validation/validation_result.dart';
import '../../../managed_copy/application/check_managed_copy_health.dart';
import '../../domain/entities/document_aggregate.dart';
import '../../domain/entities/draft_save_input.dart';
import '../../domain/entities/review_queue_item.dart';
import '../../domain/entities/review_queue_query.dart';
import '../../domain/repositories/review_queue_repository.dart';
import '../../domain/usecases/approve_classification.dart';
import '../../domain/usecases/load_document_aggregate.dart';
import '../../domain/usecases/return_to_in_progress.dart';
import '../../domain/usecases/save_document_draft.dart';
import 'review_event.dart';
import 'review_state.dart';

/// Coordinates the (non-UI) document review/classification workflow: paging the
/// review queue, loading one document for editing, tracking unsaved edits, and
/// driving save / approve / return-to-in_progress through the existing M3 use
/// cases.
///
/// Depends only on domain use cases, the review-queue repository contract, and
/// domain entities — no Drift or filesystem types.
class ReviewBloc extends Bloc<ReviewEvent, ReviewState> {
  ReviewBloc({
    required this.queueRepository,
    required this.loadDocument,
    required this.saveDraft,
    required this.approveClassification,
    required this.returnToInProgress,
    this.checkManagedCopyHealth,
    this.pageSize = 50,
  }) : super(const ReviewState()) {
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'must be between 1 and 200',
      );
    }
    on<ReviewStarted>(_onStarted);
    on<ReviewQueueScopeChanged>(_onScopeChanged);
    on<ReviewNextPageRequested>(_onNextPage);
    on<ReviewDocumentSelected>(_onDocumentSelected);
    on<ReviewSelectionChangeConfirmed>(_onSelectionConfirmed);
    on<ReviewSelectionChangeCancelled>(_onSelectionCancelled);
    on<ReviewDraftEdited>(_onDraftEdited);
    on<ReviewDraftSaved>(_onDraftSaved);
    on<ReviewClassificationApproved>(_onApproved);
    on<ReviewReturnedToInProgress>(_onReturnedToInProgress);
    on<ReviewRetryRequested>(_onRetry);
    on<ReviewRefreshRequested>(_onRefresh);
  }

  final ReviewQueueRepository queueRepository;
  final LoadDocumentAggregate loadDocument;
  final SaveDocumentDraft saveDraft;
  final ApproveClassification approveClassification;
  final ReturnToInProgress returnToInProgress;

  /// Optional: when provided, called after loading a 'copied_to_library'
  /// document to detect and reconcile a missing physical managed-copy file
  /// (M8.6). When null the health check is skipped (e.g., in tests that do
  /// not exercise the managed-copy feature).
  final CheckManagedCopyHealth? checkManagedCopyHealth;

  final int pageSize;

  /// Monotonic generations guard against stale async results overwriting newer
  /// selections / queue loads.
  int _loadVersion = 0;
  int _queueVersion = 0;

  // --- queue ---

  Future<void> _onStarted(
    ReviewStarted event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.queueStatus != ReviewQueueStatus.initial) return;
    await _loadQueueFirstPage(emit);
  }

  Future<void> _onScopeChanged(
    ReviewQueueScopeChanged event,
    Emitter<ReviewState> emit,
  ) async {
    if (event.scope == state.scope) return;
    emit(state.copyWith(scope: event.scope));
    await _loadQueueFirstPage(emit);
  }

  Future<void> _onNextPage(
    ReviewNextPageRequested event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.queueStatus != ReviewQueueStatus.success ||
        state.isLoadingMoreQueue ||
        !state.hasMoreQueue) {
      return;
    }
    final int version = _queueVersion;
    emit(state.copyWith(isLoadingMoreQueue: true, clearQueueError: true));
    try {
      final page = await queueRepository.getQueue(
        ReviewQueueQuery(
          scope: state.scope,
          offset: state.queueItems.length,
          limit: pageSize,
        ),
      );
      if (version != _queueVersion || emit.isDone) return;
      emit(
        state.copyWith(
          queueItems: [...state.queueItems, ...page.items],
          queueTotalCount: page.totalCount,
          isLoadingMoreQueue: false,
          clearQueueError: true,
        ),
      );
    } catch (_) {
      if (version != _queueVersion || emit.isDone) return;
      emit(
        state.copyWith(
          isLoadingMoreQueue: false,
          queueErrorKey: 'review_queue_next_page_failed',
        ),
      );
    }
  }

  /// Loads the first page of the current scope, optionally with a wider [limit]
  /// to preserve an already-loaded window after a workflow change.
  Future<void> _loadQueueFirstPage(
    Emitter<ReviewState> emit, {
    int? limit,
  }) async {
    int effectiveLimit = limit ?? pageSize;
    if (effectiveLimit < 1) effectiveLimit = 1;
    if (effectiveLimit > 200) effectiveLimit = 200;
    final int version = ++_queueVersion;
    emit(
      state.copyWith(
        queueStatus: ReviewQueueStatus.loading,
        queueItems: const [],
        queueTotalCount: 0,
        isLoadingMoreQueue: false,
        clearQueueError: true,
      ),
    );
    try {
      final page = await queueRepository.getQueue(
        ReviewQueueQuery(scope: state.scope, offset: 0, limit: effectiveLimit),
      );
      if (version != _queueVersion || emit.isDone) return;
      emit(
        state.copyWith(
          queueStatus: ReviewQueueStatus.success,
          queueItems: page.items,
          queueTotalCount: page.totalCount,
          clearQueueError: true,
        ),
      );
    } catch (_) {
      if (version != _queueVersion || emit.isDone) return;
      emit(
        state.copyWith(
          queueStatus: ReviewQueueStatus.failure,
          queueItems: const [],
          queueTotalCount: 0,
          queueErrorKey: 'review_queue_load_failed',
        ),
      );
    }
  }

  int _preservedLimit() {
    final int len = state.queueItems.length;
    return len > pageSize ? len : pageSize;
  }

  // --- selection / document loading ---

  Future<void> _onDocumentSelected(
    ReviewDocumentSelected event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.isBusy) return;
    final int id = event.documentId;
    if (!event.force) {
      final bool alreadyShown =
          id == state.selectedDocumentId &&
          state.documentStatus == ReviewDocumentStatus.loaded;
      if (alreadyShown) {
        // Only re-load when the M8.6 health check is relevant: a
        // 'copied_to_library' document or one with a known-missing managed
        // copy may have its status changed by the health check, so we need a
        // fresh aggregate. For every other status the reload is unnecessary
        // and would emit a loading spinner that discards unsaved edits.
        final needsHealthCheck =
            checkManagedCopyHealth != null &&
            (state.aggregate?.workflowStatusKey ==
                    WorkflowStatusKey.copiedToLibrary ||
                (state.aggregate?.files.any(
                      (f) =>
                          f.fileRoleKey == FileRoleKey.managedCopy &&
                          f.fileHealthKey == FileHealthKey.missing,
                    ) ??
                    false));
        if (needsHealthCheck && !state.isDirty) await _loadDocument(id, emit);
        return;
      }
      // Selecting a different document with unsaved edits must not silently
      // discard them: record a pending selection requiring confirmation.
      if (state.isDirty && id != state.selectedDocumentId) {
        emit(state.copyWith(pendingSelectionId: id));
        return;
      }
    }
    await _loadDocument(id, emit);
  }

  Future<void> _onSelectionConfirmed(
    ReviewSelectionChangeConfirmed event,
    Emitter<ReviewState> emit,
  ) async {
    final int? pending = state.pendingSelectionId;
    if (pending == null || state.isBusy) return;
    await _loadDocument(pending, emit);
  }

  void _onSelectionCancelled(
    ReviewSelectionChangeCancelled event,
    Emitter<ReviewState> emit,
  ) {
    if (state.pendingSelectionId == null) return;
    emit(state.copyWith(clearPendingSelection: true));
  }

  Future<void> _loadDocument(int id, Emitter<ReviewState> emit) async {
    final int version = ++_loadVersion;
    emit(
      state.copyWith(
        selectedDocumentId: id,
        documentStatus: ReviewDocumentStatus.loading,
        clearAggregate: true,
        clearDraft: true,
        validationErrors: const [],
        clearPendingSelection: true,
        clearDocumentError: true,
        clearOperationError: true,
      ),
    );
    try {
      DocumentAggregate? agg = await loadDocument.call(id);
      if (version != _loadVersion || emit.isDone) return;
      if (agg == null) {
        emit(state.copyWith(documentStatus: ReviewDocumentStatus.notFound));
        return;
      }

      // M8.6: when a 'copied_to_library' document is opened, verify the
      // physical managed-copy file exists. If missing, the health check marks
      // the row 'missing', appends an audit event, and downgrades the document
      // to 'classified' so re-copy is possible. Reload the aggregate to
      // reflect the updated state before emitting.
      final hasMissingManagedCopy = agg.files.any(
        (file) =>
            file.fileRoleKey == FileRoleKey.managedCopy &&
            file.fileHealthKey == FileHealthKey.missing,
      );
      if ((agg.workflowStatusKey == WorkflowStatusKey.copiedToLibrary ||
              hasMissingManagedCopy) &&
          checkManagedCopyHealth != null) {
        final healthResult = await checkManagedCopyHealth!.call(id);
        if (version != _loadVersion || emit.isDone) return;
        final shouldReloadAfterHealthCheck =
            hasMissingManagedCopy ||
            healthResult == CheckManagedCopyHealthResult.missingReconciled ||
            healthResult == CheckManagedCopyHealthResult.alreadyMissing;
        if (shouldReloadAfterHealthCheck &&
            healthResult != CheckManagedCopyHealthResult.reconciliationFailed) {
          agg = await loadDocument.call(id);
          if (version != _loadVersion || emit.isDone) return;
          if (agg == null) {
            emit(state.copyWith(documentStatus: ReviewDocumentStatus.notFound));
            return;
          }
        }
      }

      // Only a *fresh* selection may suggest a title from the filename, so a
      // suggestion is never re-applied when the same document is reloaded after
      // a save/return (which would re-overwrite a title the user edited or
      // cleared during the current selection).
      _emitLoaded(emit, agg, suggestTitle: true);
    } catch (_) {
      if (version != _loadVersion || emit.isDone) return;
      emit(
        state.copyWith(
          documentStatus: ReviewDocumentStatus.failure,
          documentErrorKey: 'review_document_load_failed',
        ),
      );
    }
  }

  void _emitLoaded(
    Emitter<ReviewState> emit,
    DocumentAggregate agg, {
    bool suggestTitle = false,
  }) {
    final DraftSaveInput baseline = DraftSaveInput.fromAggregate(agg);
    // The baseline always mirrors persisted state, so unsaved-change tracking
    // stays correct. When a fresh selection has no title, the *draft* (not the
    // baseline) is seeded with a filename-derived suggestion, which marks the
    // document dirty and therefore requires an explicit save to persist.
    DraftSaveInput draft = baseline;
    if (suggestTitle) {
      final String existingTitle = baseline.common.title?.trim() ?? '';
      if (existingTitle.isEmpty) {
        final String? suggestion = _titleFromFileName(
          agg.preferredSourceFileName,
        );
        if (suggestion != null) {
          draft = baseline.copyWith(
            common: baseline.common.copyWith(title: suggestion),
          );
        }
      }
    }
    emit(
      _stateWithQueueItemSynced(agg).copyWith(
        documentStatus: ReviewDocumentStatus.loaded,
        aggregate: agg,
        baselineDraft: baseline,
        draft: draft,
        validationErrors: const [],
        clearDocumentError: true,
      ),
    );
  }

  ReviewState _stateWithQueueItemSynced(DocumentAggregate agg) {
    final index = state.queueItems.indexWhere(
      (item) => item.id == agg.documentId,
    );
    if (index < 0) return state;

    final item = state.queueItems[index];
    if (item.workflowStatusKey == agg.workflowStatusKey &&
        item.documentCode == agg.documentCode &&
        item.title == agg.common.title) {
      return state;
    }

    final updatedItems = [...state.queueItems];
    updatedItems[index] = ReviewQueueItem(
      id: item.id,
      workflowStatusKey: agg.workflowStatusKey,
      updatedAt: item.updatedAt,
      documentCode: agg.documentCode ?? item.documentCode,
      title: agg.common.title,
      sourceFileName: item.sourceFileName,
      documentTypeNameAr: item.documentTypeNameAr,
    );
    return state.copyWith(queueItems: updatedItems);
  }

  /// Derives a suggested title from a source filename by removing only the final
  /// extension. Preserves Arabic, spaces, and other Unicode text. Returns `null`
  /// when there is no usable filename.
  ///
  /// Examples: `constitutional_law.pdf` -> `constitutional_law`;
  /// `book.final.pdf` -> `book.final`.
  static String? _titleFromFileName(String? fileName) {
    final String trimmed = fileName?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final int dot = trimmed.lastIndexOf('.');
    // Strip the final extension only when the dot is a real separator (not a
    // leading dot, and not a trailing dot with no extension after it).
    if (dot > 0 && dot < trimmed.length - 1) {
      final String base = trimmed.substring(0, dot).trim();
      return base.isEmpty ? trimmed : base;
    }
    return trimmed;
  }

  // --- editing ---

  void _onDraftEdited(ReviewDraftEdited event, Emitter<ReviewState> emit) {
    if (state.documentStatus != ReviewDocumentStatus.loaded) return;
    if (event.draft.documentId != state.selectedDocumentId) return;
    emit(
      state.copyWith(
        draft: event.draft,
        validationErrors: const [],
        clearOperationError: true,
      ),
    );
  }

  // --- mutating operations (overlap-guarded) ---

  Future<void> _onDraftSaved(
    ReviewDraftSaved event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.isBusy) return;
    final int? docId = state.selectedDocumentId;
    final DraftSaveInput? draft = state.draft;
    if (state.documentStatus != ReviewDocumentStatus.loaded ||
        docId == null ||
        draft == null) {
      return;
    }
    emit(
      state.copyWith(
        operation: ReviewOperation.saving,
        validationErrors: const [],
        clearOperationError: true,
      ),
    );
    try {
      final ValidationResult result = await saveDraft.call(draft);
      if (emit.isDone) return;
      if (result.isInvalid) {
        emit(
          state.copyWith(
            operation: ReviewOperation.none,
            validationErrors: result.errors,
          ),
        );
        return;
      }
      // Saving keeps the current document selected and refreshes its persisted
      // state (and resets the dirty baseline).
      final DocumentAggregate? agg = await loadDocument.call(docId);
      if (emit.isDone) return;
      if (agg == null) {
        emit(
          state.copyWith(
            operation: ReviewOperation.none,
            documentStatus: ReviewDocumentStatus.notFound,
            clearAggregate: true,
            clearDraft: true,
          ),
        );
        return;
      }
      emit(state.copyWith(operation: ReviewOperation.none));
      _emitLoaded(emit, agg);
    } catch (_) {
      if (emit.isDone) return;
      emit(
        state.copyWith(
          operation: ReviewOperation.none,
          operationErrorKey: 'review_save_failed',
        ),
      );
    }
  }

  Future<void> _onApproved(
    ReviewClassificationApproved event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.isBusy) return;
    final int? docId = state.selectedDocumentId;
    if (state.documentStatus != ReviewDocumentStatus.loaded || docId == null) {
      return;
    }
    emit(
      state.copyWith(
        operation: ReviewOperation.approving,
        validationErrors: const [],
        clearOperationError: true,
      ),
    );
    try {
      final ValidationResult result = await approveClassification.call(docId);
      if (emit.isDone) return;
      if (result.isInvalid) {
        emit(
          state.copyWith(
            operation: ReviewOperation.none,
            validationErrors: result.errors,
          ),
        );
        return;
      }
      // Determine the next queue document BEFORE refreshing (the approved one
      // leaves the default queue once classified).
      final int? nextId = _nextQueueIdAfter(docId);
      await _loadQueueFirstPage(emit, limit: _preservedLimit());
      if (emit.isDone) return;
      final bool nextAvailable =
          nextId != null && state.queueItems.any((i) => i.id == nextId);
      if (nextAvailable) {
        emit(state.copyWith(operation: ReviewOperation.none));
        await _loadDocument(nextId, emit);
      } else {
        emit(
          state.copyWith(
            operation: ReviewOperation.none,
            clearSelectedDocument: true,
            documentStatus: ReviewDocumentStatus.none,
            clearAggregate: true,
            clearDraft: true,
            validationErrors: const [],
          ),
        );
      }
    } catch (_) {
      if (emit.isDone) return;
      emit(
        state.copyWith(
          operation: ReviewOperation.none,
          operationErrorKey: 'review_approve_failed',
        ),
      );
    }
  }

  Future<void> _onReturnedToInProgress(
    ReviewReturnedToInProgress event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.isBusy) return;
    final int? docId = state.selectedDocumentId;
    if (state.documentStatus != ReviewDocumentStatus.loaded || docId == null) {
      return;
    }
    emit(
      state.copyWith(
        operation: ReviewOperation.returning,
        validationErrors: const [],
        clearOperationError: true,
      ),
    );
    try {
      final ValidationResult result = await returnToInProgress.call(docId);
      if (emit.isDone) return;
      if (result.isInvalid) {
        emit(
          state.copyWith(
            operation: ReviewOperation.none,
            validationErrors: result.errors,
          ),
        );
        return;
      }
      final DocumentAggregate? agg = await loadDocument.call(docId);
      if (emit.isDone) return;
      // The document changes scope membership; refresh the queue.
      await _loadQueueFirstPage(emit, limit: _preservedLimit());
      if (emit.isDone) return;
      if (agg == null) {
        emit(
          state.copyWith(
            operation: ReviewOperation.none,
            documentStatus: ReviewDocumentStatus.notFound,
            clearAggregate: true,
            clearDraft: true,
          ),
        );
        return;
      }
      // Returning keeps the document selected for further editing.
      emit(state.copyWith(operation: ReviewOperation.none));
      _emitLoaded(emit, agg);
    } catch (_) {
      if (emit.isDone) return;
      emit(
        state.copyWith(
          operation: ReviewOperation.none,
          operationErrorKey: 'review_return_failed',
        ),
      );
    }
  }

  Future<void> _onRetry(
    ReviewRetryRequested event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.isBusy) return;
    if (state.documentStatus == ReviewDocumentStatus.failure &&
        state.selectedDocumentId != null) {
      await _loadDocument(state.selectedDocumentId!, emit);
      return;
    }
    if (state.queueStatus == ReviewQueueStatus.failure) {
      await _loadQueueFirstPage(emit);
      return;
    }
    if (state.queueStatus == ReviewQueueStatus.success &&
        state.queueErrorKey == 'review_queue_next_page_failed') {
      add(const ReviewNextPageRequested());
    }
  }

  Future<void> _onRefresh(
    ReviewRefreshRequested event,
    Emitter<ReviewState> emit,
  ) async {
    if (state.isBusy) return;
    final selected = state.selectedDocumentId;
    await _loadQueueFirstPage(emit, limit: _preservedLimit());
    if (emit.isDone || selected == null) return;
    await _loadDocument(selected, emit);
  }

  /// The id of the document that follows [docId] in the currently loaded queue
  /// window, or `null` if [docId] is absent or last.
  int? _nextQueueIdAfter(int docId) {
    final int index = state.queueItems.indexWhere((i) => i.id == docId);
    if (index < 0 || index + 1 >= state.queueItems.length) return null;
    return state.queueItems[index + 1].id;
  }

  @override
  Future<void> close() {
    _loadVersion++;
    _queueVersion++;
    return super.close();
  }
}
