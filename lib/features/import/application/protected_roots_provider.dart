// lib/features/import/application/protected_roots_provider.dart

import '../domain/entities/protected_roots.dart';

/// Builds the configured [ProtectedRoots] for an import run from the real
/// application-support location and optional settings, with no invented default
/// managed-library or backup paths. Implementations live in the data layer.
abstract class ProtectedRootsProvider {
  Future<ProtectedRoots> load();
}
