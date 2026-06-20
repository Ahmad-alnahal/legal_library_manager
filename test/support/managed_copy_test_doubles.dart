// Shared test doubles for managed-copy platform dependencies.

import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/documents_directory_resolver.dart';

/// A [DocumentsDirectoryResolver] that resolves no Documents path.
///
/// The production resolver calls path_provider's
/// `getApplicationDocumentsDirectory()`, a platform-channel call that never
/// completes under `flutter_test` (there is no Flutter engine to answer it).
/// Full-app widget tests that navigate to the Settings page trigger automatic
/// copy-root initialization, which awaits that call — so the Settings loading
/// spinner would animate forever and `pumpAndSettle` would time out.
///
/// Resolving to null keeps initialization fully in-process and touches neither
/// the platform nor the disk: startup degrades to the typed
/// requires-attention state, which the Settings page renders without spinning.
class StubDocumentsDirectoryResolver implements DocumentsDirectoryResolver {
  const StubDocumentsDirectoryResolver();

  @override
  Future<String?> resolveDocumentsPath() async => null;
}

/// Replaces the registered [DocumentsDirectoryResolver] with a stub that does
/// no platform or filesystem work.
///
/// Call after [configureDependencies] in widget tests that pump the full app
/// and may navigate to Settings. Registration is lazy, so swapping it here
/// (before the Settings bloc first resolves it) is picked up by the lazily
/// constructed initializer.
void useStubDocumentsDirectoryResolver() {
  if (getIt.isRegistered<DocumentsDirectoryResolver>()) {
    getIt.unregister<DocumentsDirectoryResolver>();
  }
  getIt.registerLazySingleton<DocumentsDirectoryResolver>(
    StubDocumentsDirectoryResolver.new,
  );
}
