// lib/features/import/domain/entities/protected_roots.dart

import 'package:equatable/equatable.dart';

/// The configured set of app-owned / protected filesystem roots that import must
/// never scan as a source and must never descend into.
///
/// Paths are plain strings here (persistence-agnostic, no `dart:io`). The data
/// layer canonicalizes and compares them. Optional roots are `null` when not yet
/// configured. [databaseRoot] (application-support) is always present because the
/// SQLite database lives there.
class ProtectedRoots extends Equatable {
  const ProtectedRoots({
    required this.databaseRoot,
    this.managedLibraryRoot,
    this.backupRoot,
    this.exportRoot,
    this.logRoot,
    this.additionalAppOwnedRoots = const [],
  });

  /// The database / application-support root. Always configured.
  final String databaseRoot;

  /// The managed-library root, when configured.
  final String? managedLibraryRoot;

  /// The database-backup root, when configured.
  final String? backupRoot;

  /// The export root, when configured.
  final String? exportRoot;

  /// The log root, when configured.
  final String? logRoot;

  /// Any further app-owned roots (e.g. staging) that must also be protected.
  final List<String> additionalAppOwnedRoots;

  /// Every configured protected root, with nulls removed, de-duplicated by value
  /// order (canonicalization/comparison is the data layer's job).
  List<String> get all => <String>[
    databaseRoot,
    ?managedLibraryRoot,
    ?backupRoot,
    ?exportRoot,
    ?logRoot,
    ...additionalAppOwnedRoots,
  ];

  @override
  List<Object?> get props => [
    databaseRoot,
    managedLibraryRoot,
    backupRoot,
    exportRoot,
    logRoot,
    additionalAppOwnedRoots,
  ];
}
