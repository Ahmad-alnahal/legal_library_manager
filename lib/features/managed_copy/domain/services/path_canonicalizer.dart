// lib/features/managed_copy/domain/services/path_canonicalizer.dart

/// Resolves filesystem paths to their canonical form.
///
/// Implementations live in the data layer and may import dart:io. Domain and
/// application layers depend only on this abstraction.
///
/// Canonical resolution removes `.` and `..` segments and follows symbolic
/// links and Windows junctions/reparse points. Two paths that alias the same
/// filesystem location will produce identical canonical outputs.
abstract class PathCanonicalizer {
  /// Returns the canonical absolute path for [path], resolving symlinks,
  /// junctions, and `..` segments.
  ///
  /// Returns null when [path] does not exist, cannot be resolved, or would
  /// require elevated access to inspect. Callers must treat a null result as
  /// an unresolvable (and therefore unsafe) path.
  String? canonicalize(String path);
}
