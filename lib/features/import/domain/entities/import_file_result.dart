// lib/features/import/domain/entities/import_file_result.dart

import 'package:equatable/equatable.dart';

import 'import_error.dart';

/// The single outcome assigned to each scanned file, per the import spec.
///
/// The [key] values are also the exact `import_batch_files.result_key` strings.
enum ImportFileOutcome {
  importedNew('imported_new'),
  importedDuplicatePath('imported_duplicate_path'),
  alreadyImported('already_imported'),
  unsupportedType('unsupported_type'),
  unreadable('unreadable'),
  hashFailed('hash_failed'),
  scanFailed('scan_failed'),

  /// The file is structurally corrupted (e.g. zero-byte, missing `%PDF-`
  /// header). Stored as `result_key = 'corrupted'` in import_batch_files.
  /// Never hashed or added to a duplicate group.
  corrupted('corrupted');

  const ImportFileOutcome(this.key);

  /// Stable database/result key.
  final String key;
}

/// The result of importing a single discovered file.
///
/// [documentId] and [fileId] are set when a database row was created or matched.
/// They are `null` for outcomes with no file row (e.g. `unsupported_type`,
/// `scan_failed`). [error] is set for failure outcomes.
class ImportFileResult extends Equatable {
  const ImportFileResult({
    required this.outcome,
    this.documentId,
    this.fileId,
    this.error,
  });

  final ImportFileOutcome outcome;
  final int? documentId;
  final int? fileId;
  final ImportError? error;

  @override
  List<Object?> get props => [outcome, documentId, fileId, error];
}
