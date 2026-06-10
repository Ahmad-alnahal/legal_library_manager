import 'package:equatable/equatable.dart';

import '../../../../core/validation/validation_error.dart';
import '../../domain/entities/document_aggregate.dart';
import '../../domain/entities/draft_save_input.dart';
import '../../domain/entities/review_queue_item.dart';
import '../../domain/entities/review_queue_query.dart';

enum ReviewQueueStatus { initial, loading, success, failure }

enum ReviewDocumentStatus { none, loading, loaded, notFound, failure }

/// Which mutating operation (if any) is currently in flight. Used to prevent
/// overlapping save/approve/return operations.
enum ReviewOperation { none, saving, approving, returning }

class ReviewState extends Equatable {
  const ReviewState({
    this.scope = ReviewQueueScope.reviewQueue,
    this.queueStatus = ReviewQueueStatus.initial,
    this.queueItems = const [],
    this.queueTotalCount = 0,
    this.isLoadingMoreQueue = false,
    this.selectedDocumentId,
    this.documentStatus = ReviewDocumentStatus.none,
    this.aggregate,
    this.baselineDraft,
    this.draft,
    this.operation = ReviewOperation.none,
    this.pendingSelectionId,
    this.validationErrors = const [],
    this.queueErrorKey,
    this.documentErrorKey,
    this.operationErrorKey,
  });

  /// Current queue filter.
  final ReviewQueueScope scope;

  /// Queue (list) loading state.
  final ReviewQueueStatus queueStatus;
  final List<ReviewQueueItem> queueItems;
  final int queueTotalCount;
  final bool isLoadingMoreQueue;

  /// Selected/loaded document state.
  final int? selectedDocumentId;
  final ReviewDocumentStatus documentStatus;

  /// The persisted snapshot of the selected document.
  final DocumentAggregate? aggregate;

  /// The draft baseline derived from [aggregate] when it loaded; unsaved-change
  /// detection compares [draft] against this.
  final DraftSaveInput? baselineDraft;

  /// The current, possibly-edited in-memory draft.
  final DraftSaveInput? draft;

  /// The mutating operation currently in flight, if any.
  final ReviewOperation operation;

  /// When set, a selection change to this document is pending confirmation
  /// because the current document has unsaved edits.
  final int? pendingSelectionId;

  /// Structured field errors from the last save/approve/return attempt. Already
  /// safe to surface (stable field/code pairs, developer-facing messages).
  final List<ValidationError> validationErrors;

  /// Safe internal error keys (never stack traces) for each failure surface.
  final String? queueErrorKey;
  final String? documentErrorKey;
  final String? operationErrorKey;

  /// True when the current draft differs from the loaded baseline.
  bool get isDirty =>
      draft != null && baselineDraft != null && draft != baselineDraft;

  /// True when a selection change is awaiting confirmation.
  bool get requiresSelectionConfirmation => pendingSelectionId != null;

  /// True when a mutating operation is in flight.
  bool get isBusy => operation != ReviewOperation.none;

  bool get hasMoreQueue => queueItems.length < queueTotalCount;

  ReviewState copyWith({
    ReviewQueueScope? scope,
    ReviewQueueStatus? queueStatus,
    List<ReviewQueueItem>? queueItems,
    int? queueTotalCount,
    bool? isLoadingMoreQueue,
    int? selectedDocumentId,
    bool clearSelectedDocument = false,
    ReviewDocumentStatus? documentStatus,
    DocumentAggregate? aggregate,
    bool clearAggregate = false,
    DraftSaveInput? baselineDraft,
    DraftSaveInput? draft,
    bool clearDraft = false,
    ReviewOperation? operation,
    int? pendingSelectionId,
    bool clearPendingSelection = false,
    List<ValidationError>? validationErrors,
    String? queueErrorKey,
    bool clearQueueError = false,
    String? documentErrorKey,
    bool clearDocumentError = false,
    String? operationErrorKey,
    bool clearOperationError = false,
  }) {
    return ReviewState(
      scope: scope ?? this.scope,
      queueStatus: queueStatus ?? this.queueStatus,
      queueItems: queueItems ?? this.queueItems,
      queueTotalCount: queueTotalCount ?? this.queueTotalCount,
      isLoadingMoreQueue: isLoadingMoreQueue ?? this.isLoadingMoreQueue,
      selectedDocumentId: clearSelectedDocument
          ? null
          : selectedDocumentId ?? this.selectedDocumentId,
      documentStatus: documentStatus ?? this.documentStatus,
      aggregate: clearAggregate ? null : aggregate ?? this.aggregate,
      baselineDraft: clearDraft ? null : baselineDraft ?? this.baselineDraft,
      draft: clearDraft ? null : draft ?? this.draft,
      operation: operation ?? this.operation,
      pendingSelectionId: clearPendingSelection
          ? null
          : pendingSelectionId ?? this.pendingSelectionId,
      validationErrors: validationErrors ?? this.validationErrors,
      queueErrorKey: clearQueueError
          ? null
          : queueErrorKey ?? this.queueErrorKey,
      documentErrorKey: clearDocumentError
          ? null
          : documentErrorKey ?? this.documentErrorKey,
      operationErrorKey: clearOperationError
          ? null
          : operationErrorKey ?? this.operationErrorKey,
    );
  }

  @override
  List<Object?> get props => [
    scope,
    queueStatus,
    queueItems,
    queueTotalCount,
    isLoadingMoreQueue,
    selectedDocumentId,
    documentStatus,
    aggregate,
    baselineDraft,
    draft,
    operation,
    pendingSelectionId,
    validationErrors,
    queueErrorKey,
    documentErrorKey,
    operationErrorKey,
  ];
}
