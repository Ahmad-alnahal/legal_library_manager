// lib/features/import/domain/services/folder_validator.dart

import '../entities/folder_validation.dart';
import '../entities/protected_roots.dart';

/// Validates a candidate source folder against safety boundaries before any
/// scan. Implementations live in the data layer and use filesystem/path APIs;
/// this contract stays free of `dart:io`.
abstract class FolderValidator {
  /// Resolves and validates [sourceFolder] against [protectedRoots].
  ///
  /// Never creates, mutates, moves, renames, or deletes anything.
  Future<FolderValidationResult> validate(
    String sourceFolder, {
    required ProtectedRoots protectedRoots,
  });
}
