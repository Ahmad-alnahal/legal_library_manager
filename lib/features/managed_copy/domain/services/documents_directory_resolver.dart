// lib/features/managed_copy/domain/services/documents_directory_resolver.dart

/// Resolves the current user's Documents directory.
///
/// Implementations live in the data layer and may use path_provider or other
/// platform channels. Domain and application layers depend only on this
/// abstraction.
abstract class DocumentsDirectoryResolver {
  /// Returns the absolute path of the user's Documents directory, or null
  /// when it cannot be resolved. Implementations must never throw.
  Future<String?> resolveDocumentsPath();
}
