// lib/features/import/domain/entities/import_request.dart

import 'package:equatable/equatable.dart';

import 'protected_roots.dart';

/// A request to import PDFs from a user-selected source folder.
///
/// Persistence- and filesystem-agnostic: the data layer validates and scans the
/// [sourceFolder] using the configured [protectedRoots].
class ImportRequest extends Equatable {
  const ImportRequest({
    required this.sourceFolder,
    required this.recursive,
    required this.protectedRoots,
  });

  /// The user-selected folder to scan. Validated before any scan begins.
  final String sourceFolder;

  /// When true, descend into subfolders; otherwise scan only the top level.
  final bool recursive;

  /// The app-owned roots that must never be scanned or descended into.
  final ProtectedRoots protectedRoots;

  @override
  List<Object?> get props => [sourceFolder, recursive, protectedRoots];
}
