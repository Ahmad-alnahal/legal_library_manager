// lib/features/file_open/domain/repositories/file_open_repository.dart

import '../entities/file_open_record.dart';
import '../entities/open_target.dart';

/// Persistence boundary for the safe-open workflow.
///
/// Implementations read from [document_files] and append to
/// [file_open_events]. They must never modify [documents],
/// [document_files], workflow statuses, or source files.
abstract class FileOpenRepository {
  /// Loads the minimal [FileOpenRecord] for [fileId] from [document_files].
  ///
  /// Returns null if no row with that ID exists.
  Future<FileOpenRecord?> loadFileRecord(int fileId);

  /// Appends one row to [file_open_events].
  ///
  /// [documentId] may be null when the file record was not found (the FK
  /// constraint may prevent insertion in that case; callers swallow the
  /// resulting error). [errorCode] and [messageSafe] must be stable, safe
  /// strings — never raw exception messages or document contents.
  Future<void> recordOpenEvent({
    required int fileId,
    required int? documentId,
    required OpenTarget target,
    required String resultKey,
    String? errorCode,
    String? messageSafe,
  });
}
