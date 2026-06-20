// lib/core/di/injection.dart

import 'package:get_it/get_it.dart';

import '../../features/duplicates/data/repositories/drift_duplicate_review_repository.dart';
import '../../features/duplicates/domain/repositories/duplicate_review_repository.dart';
import '../../features/duplicates/presentation/bloc/duplicate_review_bloc.dart';
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
import '../../features/file_open/application/open_file_use_case.dart';
import '../../features/managed_copy/application/apply_default_copy_roots.dart';
import '../../features/managed_copy/application/check_managed_copy_health.dart';
import '../../features/managed_copy/application/configure_copy_roots.dart';
import '../../features/managed_copy/application/initialize_copy_roots.dart';
import '../../features/managed_copy/application/managed_copy_use_case.dart';
import '../../features/managed_copy/application/repair_copy_root.dart';
import '../../features/managed_copy/data/repositories/drift_managed_copy_repository.dart';
import '../../features/managed_copy/data/services/default_operation_id_generator.dart';
import '../../features/managed_copy/data/services/file_picker_copy_root_picker.dart';
import '../../features/managed_copy/data/services/path_provider_documents_directory_resolver.dart';
import '../../features/managed_copy/data/services/sqlite_database_backup_service.dart';
import '../../features/managed_copy/data/services/windows_managed_library_filesystem.dart';
import '../../features/managed_copy/data/services/windows_path_canonicalizer.dart';
import '../../features/managed_copy/domain/repositories/managed_copy_repository.dart';
import '../../features/managed_copy/domain/services/database_backup_service.dart';
import '../../features/managed_copy/domain/services/copy_root_picker.dart';
import '../../features/managed_copy/domain/services/documents_directory_resolver.dart';
import '../../features/managed_copy/domain/services/managed_library_filesystem.dart';
import '../../features/managed_copy/domain/services/operation_id_generator.dart';
import '../../features/managed_copy/domain/services/path_canonicalizer.dart';
import '../../features/managed_copy/presentation/bloc/copy_settings_bloc.dart';
import '../../features/managed_copy/presentation/bloc/managed_copy_bloc.dart';
import '../../features/file_open/data/repositories/drift_file_open_repository.dart';
import '../../features/file_open/data/services/file_system_existence_checker.dart';
import '../../features/file_open/data/services/windows_os_file_opener.dart';
import '../../features/file_open/domain/repositories/file_open_repository.dart';
import '../../features/file_open/domain/services/file_existence_checker.dart';
import '../../features/file_open/domain/services/os_file_opener.dart';
import '../../features/file_open/presentation/bloc/file_open_bloc.dart';
import '../../features/reference/data/repositories/drift_reference_repository.dart';
import '../../features/reference/domain/repositories/reference_repository.dart';
import '../../features/shell/presentation/bloc/navigation_bloc.dart';
import '../database/app_database.dart';
import '../time/clock.dart';

/// Global service locator.
final GetIt getIt = GetIt.instance;

/// Registers application dependencies (M1 shell + M4 import + M5 documents + M7 file open + M8.1–M8.6 managed copy + M9.1 duplicate review).
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
        checkManagedCopyHealth: getIt<CheckManagedCopyHealth>(),
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
    )
    // M7.1 safe-open foundation: DB-backed repository, Windows OS invoker,
    // filesystem existence checker, and orchestrating use case. Not wired into
    // any UI yet; presentation integration is deferred to M7.2.
    ..registerLazySingleton<FileOpenRepository>(
      () => DriftFileOpenRepository(getIt<AppDatabase>(), getIt<Clock>()),
    )
    ..registerLazySingleton<FileExistenceChecker>(
      FileSystemExistenceChecker.new,
    )
    ..registerLazySingleton<OsFileOpener>(WindowsOsFileOpener.new)
    ..registerLazySingleton<OpenFileUseCase>(
      () => OpenFileUseCase(
        repository: getIt<FileOpenRepository>(),
        existenceChecker: getIt<FileExistenceChecker>(),
        osOpener: getIt<OsFileOpener>(),
      ),
    )
    // M7.2 safe-open UI controller. A fresh instance per page; depends only on
    // the M7.1 use case. The presentation layer drives opening exclusively
    // through this controller, never the use case directly.
    ..registerFactory<FileOpenBloc>(
      () => FileOpenBloc(getIt<OpenFileUseCase>()),
    )
    // M8.1 managed-copy foundation: repository, filesystem, backup service,
    // and orchestrating use case. Not wired into UI yet; presentation
    // integration is deferred to M8.2.
    ..registerLazySingleton<ManagedCopyRepository>(
      () => DriftManagedCopyRepository(getIt<AppDatabase>(), getIt<Clock>()),
    )
    ..registerLazySingleton<ManagedLibraryFilesystem>(
      WindowsManagedLibraryFilesystem.new,
    )
    ..registerLazySingleton<DatabaseBackupService>(
      () => SqliteDatabaseBackupService(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<PathCanonicalizer>(WindowsPathCanonicalizer.new)
    ..registerLazySingleton<OperationIdGenerator>(
      DefaultOperationIdGenerator.new,
    )
    ..registerLazySingleton<CopyRootPicker>(FilePickerCopyRootPicker.new)
    ..registerLazySingleton<ManagedCopyUseCase>(
      () => ManagedCopyUseCase(
        repository: getIt<ManagedCopyRepository>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        backupService: getIt<DatabaseBackupService>(),
        hasher: getIt<FileHasher>(),
        clock: getIt<Clock>(),
        pathCanonicalizer: getIt<PathCanonicalizer>(),
        operationIdGenerator: getIt<OperationIdGenerator>(),
      ),
    )
    ..registerLazySingleton<ConfigureCopyRoots>(
      () => ConfigureCopyRoots(
        getIt<ManagedCopyRepository>(),
        getIt<ManagedLibraryFilesystem>(),
        getIt<PathCanonicalizer>(),
      ),
    )
    // M8.4 automatic safe copy-root setup: resolves the Documents folder in
    // the data layer and orchestrates default-root creation at startup.
    ..registerLazySingleton<DocumentsDirectoryResolver>(
      PathProviderDocumentsDirectoryResolver.new,
    )
    ..registerLazySingleton<InitializeCopyRoots>(
      () => InitializeCopyRoots(
        repository: getIt<ManagedCopyRepository>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        documentsResolver: getIt<DocumentsDirectoryResolver>(),
        configureCopyRoots: getIt<ConfigureCopyRoots>(),
      ),
    )
    // M8.5 explicit missing-folder repair: recreates exactly one configured
    // root after user confirmation, reusing the filesystem and canonicalizer.
    ..registerLazySingleton<RepairCopyRoot>(
      () => RepairCopyRoot(
        getIt<ManagedCopyRepository>(),
        getIt<ManagedLibraryFilesystem>(),
        getIt<PathCanonicalizer>(),
      ),
    )
    // M8.6 Part A: reset both roots to MARJIY defaults; delegates safety
    // validation and persistence to the existing ConfigureCopyRoots use case.
    ..registerLazySingleton<ApplyDefaultCopyRoots>(
      () => ApplyDefaultCopyRoots(
        documentsResolver: getIt<DocumentsDirectoryResolver>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        configureCopyRoots: getIt<ConfigureCopyRoots>(),
      ),
    )
    // M8.6 Part B: detects a physically missing managed-copy file and
    // reconciles the DB record (marks missing, downgrades workflow status).
    ..registerLazySingleton<CheckManagedCopyHealth>(
      () => CheckManagedCopyHealth(
        repository: getIt<ManagedCopyRepository>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        hasher: getIt<FileHasher>(),
        operationIdGenerator: getIt<OperationIdGenerator>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerFactory<ManagedCopyBloc>(
      () => ManagedCopyBloc(getIt<ManagedCopyUseCase>()),
    )
    ..registerFactory<CopySettingsBloc>(
      () => CopySettingsBloc(
        getIt<CopyRootPicker>(),
        getIt<ConfigureCopyRoots>(),
        getIt<InitializeCopyRoots>(),
        getIt<RepairCopyRoot>(),
        getIt<ApplyDefaultCopyRoots>(),
      ),
    )
    // M9.1 duplicate review: read-only repository and BLoC.
    ..registerLazySingleton<DuplicateReviewRepository>(
      () => DriftDuplicateReviewRepository(getIt<AppDatabase>()),
    )
    ..registerFactory<DuplicateReviewBloc>(
      () => DuplicateReviewBloc(repository: getIt<DuplicateReviewRepository>()),
    );
}
