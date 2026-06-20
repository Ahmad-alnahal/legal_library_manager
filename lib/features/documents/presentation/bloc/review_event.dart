import 'package:equatable/equatable.dart';

import '../../domain/entities/draft_save_input.dart';
import '../../domain/entities/review_queue_query.dart';

sealed class ReviewEvent extends Equatable {
  const ReviewEvent();

  @override
  List<Object?> get props => [];
}

/// Initial queue load (first page of the current scope).
class ReviewStarted extends ReviewEvent {
  const ReviewStarted();
}

/// Switch the queue filter between the default review queue and classified-only.
class ReviewQueueScopeChanged extends ReviewEvent {
  const ReviewQueueScopeChanged(this.scope);

  final ReviewQueueScope scope;

  @override
  List<Object?> get props => [scope];
}

/// Load the next page of the current queue.
class ReviewNextPageRequested extends ReviewEvent {
  const ReviewNextPageRequested();
}

/// Select and load a document from the queue.
///
/// When there are unsaved edits and [force] is false, selecting a *different*
/// document does not discard the edits: the BLoC records the request as a
/// pending selection requiring confirmation instead of loading.
class ReviewDocumentSelected extends ReviewEvent {
  const ReviewDocumentSelected(this.documentId, {this.force = false});

  final int documentId;
  final bool force;

  @override
  List<Object?> get props => [documentId, force];
}

/// Confirm a pending selection change, discarding the current unsaved edits and
/// loading the previously requested document.
class ReviewSelectionChangeConfirmed extends ReviewEvent {
  const ReviewSelectionChangeConfirmed();
}

/// Cancel a pending selection change and keep the current document/edits.
class ReviewSelectionChangeCancelled extends ReviewEvent {
  const ReviewSelectionChangeCancelled();
}

/// Replace the in-memory editable draft for the selected document.
class ReviewDraftEdited extends ReviewEvent {
  const ReviewDraftEdited(this.draft);

  final DraftSaveInput draft;

  @override
  List<Object?> get props => [draft];
}

/// Persist the current draft.
class ReviewDraftSaved extends ReviewEvent {
  const ReviewDraftSaved();
}

/// Approve the selected document's classification.
class ReviewClassificationApproved extends ReviewEvent {
  const ReviewClassificationApproved();
}

/// Explicitly return the selected classified document to `in_progress`.
class ReviewReturnedToInProgress extends ReviewEvent {
  const ReviewReturnedToInProgress();
}

/// Retry the last failed queue or document load.
class ReviewRetryRequested extends ReviewEvent {
  const ReviewRetryRequested();
}

/// Refreshes the queue and currently selected document after an external
/// workflow operation such as a verified managed copy.
class ReviewRefreshRequested extends ReviewEvent {
  const ReviewRefreshRequested();
}
