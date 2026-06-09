// lib/features/import/data/services/file_system_folder_validator.dart

import 'dart:io';

import '../../domain/entities/folder_validation.dart';
import '../../domain/entities/protected_roots.dart';
import '../../domain/services/folder_validator.dart';
import 'windows_path_policy.dart';

/// Filesystem-backed [FolderValidator].
///
/// Resolves canonical paths and enforces the source-folder safety boundaries
/// from the workflow spec. Read-only: it never creates, mutates, moves,
/// renames, or deletes anything.
class FileSystemFolderValidator implements FolderValidator {
  const FileSystemFolderValidator({
    WindowsPathPolicy pathPolicy = const WindowsPathPolicy(),
  }) : _paths = pathPolicy;

  final WindowsPathPolicy _paths;

  @override
  Future<FolderValidationResult> validate(
    String sourceFolder, {
    required ProtectedRoots protectedRoots,
  }) async {
    // Existence and type.
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      sourceFolder,
      followLinks: true,
    );
    if (type == FileSystemEntityType.notFound) {
      return const FolderValidationResult(
        code: FolderValidationCode.doesNotExist,
      );
    }
    if (type != FileSystemEntityType.directory) {
      return const FolderValidationResult(
        code: FolderValidationCode.notADirectory,
      );
    }

    final String canonical = _paths.canonicalize(sourceFolder);

    // Readability: attempt a non-mutating listing.
    try {
      Directory(canonical).listSync(followLinks: false).take(1).toList();
    } on FileSystemException {
      return FolderValidationResult(
        code: FolderValidationCode.notReadable,
        canonicalPath: canonical,
      );
    }

    // Protected-root boundaries.
    final List<String> protectedCanonical = protectedRoots.all
        .map(_paths.canonicalize)
        .toList(growable: false);

    for (final String root in protectedCanonical) {
      if (_paths.isSamePath(canonical, root)) {
        return FolderValidationResult(
          code: FolderValidationCode.isProtectedRoot,
          canonicalPath: canonical,
        );
      }
    }
    for (final String root in protectedCanonical) {
      if (_paths.isStrictlyInside(canonical, root)) {
        return FolderValidationResult(
          code: FolderValidationCode.insideProtectedRoot,
          canonicalPath: canonical,
        );
      }
    }
    for (final String root in protectedCanonical) {
      if (_paths.isStrictlyInside(root, canonical)) {
        return FolderValidationResult(
          code: FolderValidationCode.containsProtectedRoot,
          canonicalPath: canonical,
        );
      }
    }

    return FolderValidationResult.valid(canonical);
  }
}
