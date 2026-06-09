// lib/features/import/domain/entities/folder_validation.dart

import 'package:equatable/equatable.dart';

/// Stable reason codes for source-folder safety validation.
enum FolderValidationCode {
  /// The folder passed every safety check.
  valid,

  /// The folder does not exist.
  doesNotExist,

  /// The path exists but is not a directory.
  notADirectory,

  /// The directory cannot be read/enumerated.
  notReadable,

  /// The selected folder is itself a protected/app-owned root.
  isProtectedRoot,

  /// The selected folder lies inside a protected/app-owned root.
  insideProtectedRoot,

  /// A protected root (e.g. the managed library) lies inside the selected
  /// folder, so scanning it would touch protected storage.
  containsProtectedRoot,
}

/// The structured outcome of validating a candidate source folder.
///
/// On success [code] is [FolderValidationCode.valid] and [canonicalPath] holds
/// the resolved absolute path. On failure [canonicalPath] may still be set when
/// the path resolved but failed a boundary rule.
class FolderValidationResult extends Equatable {
  const FolderValidationResult({required this.code, this.canonicalPath});

  const FolderValidationResult.valid(this.canonicalPath)
    : code = FolderValidationCode.valid;

  final FolderValidationCode code;
  final String? canonicalPath;

  bool get isValid => code == FolderValidationCode.valid;

  @override
  List<Object?> get props => [code, canonicalPath];
}
