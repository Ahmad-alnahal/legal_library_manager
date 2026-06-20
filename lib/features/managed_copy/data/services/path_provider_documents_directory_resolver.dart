// lib/features/managed_copy/data/services/path_provider_documents_directory_resolver.dart

import 'package:path_provider/path_provider.dart';

import '../../domain/services/documents_directory_resolver.dart';

/// path_provider-backed [DocumentsDirectoryResolver].
///
/// On Windows this resolves the current user's Documents folder. Resolution
/// failures (missing platform support, unavailable known folder) are reported
/// as null — never as an exception — so startup initialization can degrade to
/// a requires-attention state instead of crashing.
class PathProviderDocumentsDirectoryResolver
    implements DocumentsDirectoryResolver {
  const PathProviderDocumentsDirectoryResolver();

  @override
  Future<String?> resolveDocumentsPath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path.trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }
}
