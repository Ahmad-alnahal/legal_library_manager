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
import '../../features/documents/data/repositories/drift_document_metadata_repository.dart';
import '../../features/documents/data/repositories/drift_review_queue_repository.dart';
import '../../features/documents/domain/repositories/document_list_repository.dart';
import '../../features/documents/domain/repositories/document_metadata_repository.dart';
import '../../features/documents/domain/repositories/review_queue_repository.dart';
import '../../features/documents/domain/usecases/approve_classification.dart';
import '../../features/documents/domain/usecases/load_document_aggregate.dart';
import '../../features/documents/domain/usecases/return_to_in_progress.dart';
import '../../features/documents/domain/usecases/save_document_draft.dart';
import '../../features/documents/domain/usecases/validate_classification.dart';
import '../../features/documents/presentation/bloc/document_list_bloc.dart';
import '../../features/documents/presentation/bloc/review_bloc.dart';
import '../../features/categories/data/repositories/drift_category_management_repository.dart';
import '../../features/categories/domain/repositories/category_management_repository.dart';
import '../../features/categories/domain/services/category_key_generator.dart';
import '../../features/categories/domain/services/category_management_service.dart';
import '../../features/categories/presentation/bloc/category_management_bloc.dart';
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
    )
    // M6.1 review workflow foundation: metadata repository, review queue, and
    // the classification use cases reused by the review BLoC.
    ..registerLazySingleton<DocumentMetadataRepository>(
      () => DriftDocumentMetadataRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<ReviewQueueRepository>(
      () => DriftReviewQueueRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<ValidateClassification>(
      () => ValidateClassification(
        references: getIt<ReferenceRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerLazySingleton<SaveDocumentDraft>(
      () => SaveDocumentDraft(
        repository: getIt<DocumentMetadataRepository>(),
        references: getIt<ReferenceRepository>(),
        classificationValidator: getIt<ValidateClassification>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerLazySingleton<ApproveClassification>(
      () => ApproveClassification(
        repository: getIt<DocumentMetadataRepository>(),
        validator: getIt<ValidateClassification>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerLazySingleton<LoadDocumentAggregate>(
      () => LoadDocumentAggregate(getIt<DocumentMetadataRepository>()),
    )
    ..registerLazySingleton<ReturnToInProgress>(
      () => ReturnToInProgress(
        repository: getIt<DocumentMetadataRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerFactory<ReviewBloc>(
      () => ReviewBloc(
        queueRepository: getIt<ReviewQueueRepository>(),
        loadDocument: getIt<LoadDocumentAggregate>(),
        saveDraft: getIt<SaveDocumentDraft>(),
        approveClassification: getIt<ApproveClassification>(),
        returnToInProgress: getIt<ReturnToInProgress>(),
      ),
    )
    // M6.3 category management: dedicated repository, key generator, validating
    // service, and BLoC. Separate from the read-only reference repository.
    ..registerLazySingleton<CategoryManagementRepository>(
      () => DriftCategoryManagementRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<CategoryKeyGenerator>(
      DefaultCategoryKeyGenerator.new,
    )
    ..registerLazySingleton<CategoryManagementService>(
      () => CategoryManagementService(
        repository: getIt<CategoryManagementRepository>(),
        keyGenerator: getIt<CategoryKeyGenerator>(),
      ),
    )
    ..registerFactory<CategoryManagementBloc>(
      () => CategoryManagementBloc(
        repository: getIt<CategoryManagementRepository>(),
        service: getIt<CategoryManagementService>(),
      ),
    );
}
