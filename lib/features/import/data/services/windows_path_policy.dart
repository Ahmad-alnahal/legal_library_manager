// lib/features/import/data/services/windows_path_policy.dart

import 'dart:io';

import 'package:path/path.dart' as p;

/// Windows-aware, path-component-safe utilities for resolving and comparing
/// filesystem paths during import.
///
/// All comparisons are case-insensitive (Windows semantics) and operate on path
/// *components*, never raw string prefixes, so siblings that merely share a
/// string prefix (e.g. `C:\Data` and `C:\Data2`) are never treated as nested.
/// Resolution is conservative: symlinks/junctions are resolved when the target
/// exists so that boundary checks see the real path. This class never creates,
/// mutates, moves, renames, or deletes anything.
class WindowsPathPolicy {
  const WindowsPathPolicy();

  /// Returns the absolute, normalized path with symlinks/junctions resolved when
  /// the entity exists. Falls back to absolute+normalized when resolution is not
  /// possible (e.g. the path does not exist), which is the conservative choice
  /// for non-existent targets.
  String canonicalize(String inputPath) {
    final String absolute = p.normalize(p.absolute(inputPath));
    try {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        absolute,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound) {
        // Resolve junctions/symlinks to the real location for safe comparison.
        return p.normalize(File(absolute).resolveSymbolicLinksSync());
      }
    } on FileSystemException {
      // Unresolvable: fall back to the absolute normalized form below.
    }
    return absolute;
  }

  /// Splits a path into comparable lowercase components (Windows is
  /// case-insensitive). The root (drive) is normalized so `C:\` and `c:\` match.
  List<String> _componentsFor(String canonicalPath) {
    // Normalize first so separator direction (`/` vs `\`) and `.`/`..` segments
    // do not affect the root or any component comparison.
    final List<String> parts = p.split(p.normalize(canonicalPath));
    return parts
        .map((part) => part.toLowerCase())
        // Drop redundant separators that `split` can surface as empties.
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  /// True when [a] and [b] are the same path (component-wise, case-insensitive).
  bool isSamePath(String a, String b) {
    final List<String> ca = _componentsFor(a);
    final List<String> cb = _componentsFor(b);
    if (ca.length != cb.length) return false;
    for (int i = 0; i < ca.length; i++) {
      if (ca[i] != cb[i]) return false;
    }
    return true;
  }

  /// True when [child] is the same path as [ancestor] or nested strictly inside
  /// it. Uses component-prefix matching, so `C:\Data2` is NOT inside `C:\Data`.
  bool isSameOrInside(String child, String ancestor) {
    final List<String> cc = _componentsFor(child);
    final List<String> ca = _componentsFor(ancestor);
    if (cc.length < ca.length) return false;
    for (int i = 0; i < ca.length; i++) {
      if (cc[i] != ca[i]) return false;
    }
    return true;
  }

  /// True when [child] is nested strictly inside [ancestor] (not equal).
  bool isStrictlyInside(String child, String ancestor) =>
      isSameOrInside(child, ancestor) && !isSamePath(child, ancestor);
}
