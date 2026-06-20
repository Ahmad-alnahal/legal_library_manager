// lib/features/managed_copy/application/repair_copy_root.dart

import '../domain/entities/copy_roots.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/copy_root_picker.dart';
import '../domain/services/managed_library_filesystem.dart';
import '../domain/services/path_canonicalizer.dart';

/// Outcome of an explicit missing-folder repair (M8.5).
enum RepairCopyRootResult {
  /// The missing directory was safely (re)created and revalidated.
  repaired,

  /// The configured directory already existed; nothing was created. The caller
  /// should simply refresh its state.
  alreadyExists,

  /// No path is stored for the requested root, so there is nothing to repair.
  notConfigured,

  /// The configured path is not an absolute path and was not created.
  invalidPath,

  /// Creating the folder here would overlap or alias another protected location
  /// (the other root, the database root, the managed `files` directory, or a
  /// registered source folder). Nothing was created.
  unsafeOverlap,

  /// The directory structure could not be created safely.
  creationFailed,
}

/// Explicitly recreates a single configured copy root that has become missing.
///
/// M8.5 safety rules:
/// - Requires an explicit caller (the Settings re-create action); never runs on
///   startup. Startup keeps M8.4 behavior and never recreates custom roots.
/// - Validates the configured path with the same rules as manual configuration
///   ([ConfigureCopyRoots]) before and after creation: absolute path, canonical
///   resolution where possible, and no overlap/alias with the other root, the
///   database root, the managed `files` directory, or registered source folders.
/// - Creates only the missing directory structure for that exact configured
///   root. No file is ever copied, moved, renamed, deleted, or overwritten, and
///   no arbitrary child files are created.
/// - After creation, the now-existing path is canonicalized again to catch a
///   junction/symlink that would redirect it into a protected location.
class RepairCopyRoot {
  const RepairCopyRoot(this._repository, this._filesystem, this._canonicalizer);

  final ManagedCopyRepository _repository;
  final ManagedLibraryFilesystem _filesystem;
  final PathCanonicalizer _canonicalizer;

  Future<RepairCopyRootResult> call(CopyRootKind kind) async {
    final CopyRoots roots = await _repository.loadCopyRoots();
    final String? target = kind == CopyRootKind.managedLibrary
        ? roots.managedLibraryRoot
        : roots.backupRoot;
    final String? sibling = kind == CopyRootKind.managedLibrary
        ? roots.backupRoot
        : roots.managedLibraryRoot;

    if (target == null || target.trim().isEmpty) {
      return RepairCopyRootResult.notConfigured;
    }
    if (_filesystem.isExistingDirectory(target)) {
      // Already present — the action must not appear for existing folders, but
      // guard against a stale UI click. Nothing is created.
      return RepairCopyRootResult.alreadyExists;
    }
    if (!_isAbsolute(target)) {
      return RepairCopyRootResult.invalidPath;
    }

    // ── Pre-creation safety ──────────────────────────────────────────────────
    // The missing target cannot be canonicalized yet, so compare its normalized
    // literal path against the canonical (or literal) forms of every protected
    // location. Also resolve the deepest existing ancestor to catch a junction
    // that would redirect the newly created tree into a protected location.
    final List<String>? protected = await _protectedPaths(sibling);
    if (protected == null) return RepairCopyRootResult.unsafeOverlap;

    final String normalizedTarget = _normalize(target);
    for (final p in protected) {
      if (_overlaps(normalizedTarget, p)) {
        return RepairCopyRootResult.unsafeOverlap;
      }
    }

    final String? ancestor = _deepestExistingAncestor(target);
    if (ancestor != null) {
      final String? canonicalAncestor = _canonicalizer.canonicalize(ancestor);
      if (canonicalAncestor == null) return RepairCopyRootResult.unsafeOverlap;
      final String normalizedAncestor = _normalize(canonicalAncestor);
      for (final p in protected) {
        // The ancestor must not be, or sit inside, a protected root. (A
        // protected root nested *below* the ancestor is fine and unrelated.)
        if (normalizedAncestor == p || normalizedAncestor.startsWith('$p\\')) {
          return RepairCopyRootResult.unsafeOverlap;
        }
      }
    }

    // ── Create only the missing directory structure for this exact root ──────
    if (!await _createDirectoryTree(target)) {
      return RepairCopyRootResult.creationFailed;
    }

    // ── Post-creation revalidation ───────────────────────────────────────────
    // Now the directory exists, canonicalize it to resolve any alias/junction
    // and re-check overlap against the protected roots.
    if (!_filesystem.isExistingDirectory(target)) {
      return RepairCopyRootResult.creationFailed;
    }
    final String? canonicalTarget = _canonicalizer.canonicalize(target);
    if (canonicalTarget == null) return RepairCopyRootResult.unsafeOverlap;
    final String normalizedCanonicalTarget = _normalize(canonicalTarget);
    for (final p in protected) {
      if (_overlaps(normalizedCanonicalTarget, p)) {
        return RepairCopyRootResult.unsafeOverlap;
      }
    }

    return RepairCopyRootResult.repaired;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Normalized canonical (or literal) forms of every location the target root
  /// must stay separate from: the database root, the other configured root, and
  /// each registered source folder. Returns null when any existing location
  /// cannot be resolved (fail closed, mirroring manual configuration).
  Future<List<String>?> _protectedPaths(String? sibling) async {
    final result = <String>[];

    final String? db = _canonicalizer.canonicalize(
      await _repository.loadDatabaseRoot(),
    );
    if (db == null) return null;
    result.add(_normalize(db));

    if (sibling != null && sibling.trim().isNotEmpty) {
      if (_filesystem.isExistingDirectory(sibling)) {
        final String? canonical = _canonicalizer.canonicalize(sibling);
        if (canonical == null) return null;
        result.add(_normalize(canonical));
      } else {
        // The other root is also missing and cannot be canonicalized; the
        // normalized literal still blocks obvious nesting.
        result.add(_normalize(sibling));
      }
    }

    for (final sourcePath in await _repository.loadAllSourcePaths()) {
      final String? parent = _canonicalizer.canonicalize(_parent(sourcePath));
      if (parent == null) return null;
      result.add(_normalize(parent));
    }
    return result;
  }

  /// Creates the target directory and any missing ancestors, top-down, using
  /// only the safe directory boundary. Each call creates a single directory
  /// whose parent already exists, so no arbitrary tree is ever materialized
  /// beyond the exact configured root path.
  Future<bool> _createDirectoryTree(String target) async {
    for (final segment in _ancestorChain(target)) {
      if (_filesystem.isExistingDirectory(segment)) continue;
      final result = await _filesystem.ensureDirectoryExists(segment);
      if (result is! FilesystemSuccess) return false;
    }
    return _filesystem.isExistingDirectory(target);
  }

  /// Directory paths from just below the drive/UNC root down to [path]
  /// inclusive, e.g. `D:\a\b` → [`D:\a`, `D:\a\b`].
  List<String> _ancestorChain(String path) {
    final String normalized = path
        .replaceAll('/', r'\')
        .replaceFirst(RegExp(r'\\+$'), '');
    final List<String> parts = normalized.split(r'\');
    final chain = <String>[];
    if (parts.length < 2 || parts.first.isEmpty) return chain;
    String current = parts.first;
    for (var i = 1; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      current = '$current\\${parts[i]}';
      chain.add(current);
    }
    return chain;
  }

  String? _deepestExistingAncestor(String target) {
    String? deepest;
    for (final segment in _ancestorChain(target)) {
      if (_filesystem.isExistingDirectory(segment)) deepest = segment;
    }
    return deepest;
  }

  static bool _isAbsolute(String path) {
    final normalized = path.replaceAll('/', r'\');
    return RegExp(r'^[A-Za-z]:\\').hasMatch(normalized) ||
        normalized.startsWith(r'\\');
  }

  static String _normalize(String value) => value
      .replaceAll('/', r'\')
      .toLowerCase()
      .replaceFirst(RegExp(r'\\+$'), '');

  static bool _overlaps(String a, String b) =>
      a == b || a.startsWith('$b\\') || b.startsWith('$a\\');

  static String _parent(String path) {
    final normalized = path.replaceAll('/', r'\');
    final separator = normalized.lastIndexOf(r'\');
    return separator <= 2
        ? normalized.substring(0, separator + 1)
        : normalized.substring(0, separator);
  }
}
