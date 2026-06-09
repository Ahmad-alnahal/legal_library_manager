// lib/core/di/injection.dart

import 'package:get_it/get_it.dart';

import '../../features/import/application/folder_picker.dart';
import '../../features/import/application/import_coordinator.dart';
import '../../features/import/application/protected_roots_provider.dart';
import '../../features/import/data/repositories/drift_import_repository.dart';
import '../../features/import/data/services/conservative_pdf_health_inspector.dart';
import '../../features/import/data/services/file_picker_folder_picker.dart';
import '../../features/import/data/services/file_system_folder_validator.dart';
import '../../features/import/data/services/file_system_pdf_scanner.dart';
import '../../features/import/data/services/settings_protected_roots_provider.dart';
import '../../features/import/data/services/streaming_file_hasher.dart';
import '../../features/import/domain/repositories/import_repository.dart';
import '../../features/import/domain/services/file_hasher.dart';
import '../../features/import/domain/services/folder_validator.dart';
import '../../features/import/domain/services/pdf_health_inspector.dart';
import '../../features/import/domain/services/pdf_scanner.dart';
import '../../features/import/presentation/bloc/import_bloc.dart';
import '../../features/documents/data/repositories/drift_document_list_repository.dart';
import '../../features/documents/domain/repositories/document_list_repository.dart';
import '../../features/documents/presentation/bloc/document_list_bloc.dart';
import '../../features/reference/data/repositories/drift_reference_repository.dart';
import '../../features/reference/domain/repositories/reference_repository.dart';
import '../../features/shell/presentation/bloc/navigation_bloc.dart';
import '../database/app_database.dart';
import '../time/clock.dart';

/// Global service locator.
final GetIt getIt = GetIt.instance;

/// Registers application dependencies (M1 shell + M4 import + M5 documents).
///
/// The production [AppDatabase] is a single lazy singleton (its connection opens
/// lazily on first query and closes on [GetIt.reset]). Tests may register an
/// in-memory [AppDatabase] before calling this; the existing registration is
/// then reused. Constructing the import services/coordinator/BLoC performs no
/// database or filesystem work, so navigating to an idle Import screen in widget
/// tests never opens the production database.
void configureDependencies() {
  getIt.registerFactory<NavigationBloc>(NavigationBloc.new);

  if (!getIt.isRegistered<AppDatabase>()) {
    getIt.registerLazySingleton<AppDatabase>(
      AppDatabase.new,
      dispose: (db) => db.close(),
    );
  }

  // Import services (const, side-effect free).
  getIt
    ..registerLazySingleton<Clock>(SystemClock.new)
    ..registerLazySingleton<FolderValidator>(FileSystemFolderValidator.new)
    ..registerLazySingleton<PdfScanner>(FileSystemPdfScanner.new)
    ..registerLazySingleton<FileHasher>(StreamingFileHasher.new)
    ..registerLazySingleton<PdfHealthInspector>(
      ConservativePdfHealthInspector.new,
    )
    ..registerLazySingleton<FolderPicker>(FilePickerFolderPicker.new)
    ..registerLazySingleton<ImportRepository>(
      () => DriftImportRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<ProtectedRootsProvider>(
      () => SettingsProtectedRootsProvider(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<ImportCoordinator>(
      () => ImportCoordinator(
        validator: getIt<FolderValidator>(),
        scanner: getIt<PdfScanner>(),
        hasher: getIt<FileHasher>(),
        inspector: getIt<PdfHealthInspector>(),
        repository: getIt<ImportRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerFactory<ImportBloc>(
      () => ImportBloc(
        coordinator: getIt<ImportCoordinator>(),
        protectedRootsProvider: getIt<ProtectedRootsProvider>(),
      ),
    )
    ..registerLazySingleton<DocumentListRepository>(
      () => DriftDocumentListRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<ReferenceRepository>(
      () => DriftReferenceRepository(getIt<AppDatabase>()),
    )
    ..registerFactory<DocumentListBloc>(
      () => DocumentListBloc(repository: getIt<DocumentListRepository>()),
    );
}
