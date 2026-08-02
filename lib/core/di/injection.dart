// lib/core/di/injection.dart

import 'package:get_it/get_it.dart';

import '../../features/dashboard/data/repositories/drift_dashboard_repository.dart';
import '../../features/dashboard/domain/repositories/dashboard_repository.dart';
import '../../features/dashboard/presentation/bloc/dashboard_bloc.dart'
    show DashboardBloc;
import '../../features/duplicates/data/repositories/drift_duplicate_review_repository.dart';
import '../../features/duplicates/domain/repositories/duplicate_review_repository.dart';
import '../../features/duplicates/presentation/bloc/duplicate_review_bloc.dart';
import '../../features/export/application/use_cases/generate_export_batch.dart';
import '../../features/export/application/use_cases/load_export_screen_data.dart';
import '../../features/export/application/use_cases/mark_document_ready_for_export.dart';
import '../../features/export/data/repositories/drift_export_batch_repository.dart';
import '../../features/export/data/services/windows_export_filesystem.dart';
import '../../features/export/domain/repositories/export_batch_repository.dart';
import '../../features/export/domain/services/export_filesystem.dart';
import '../../features/export/presentation/bloc/export_batch_bloc.dart';
import '../../features/export/presentation/bloc/mark_ready_for_export_bloc.dart';
import '../../features/import/application/folder_picker.dart';
import '../../features/import/application/import_coordinator.dart';
import '../../features/import/application/import_job_service.dart';
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
import '../../features/import/domain/usecases/get_recent_import_batches_use_case.dart';
import '../../features/import/presentation/bloc/import_bloc.dart';
import '../../features/import/presentation/bloc/import_history_bloc.dart';
import '../../features/import/presentation/bloc/import_status_bloc.dart';
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
import '../../features/managed_copy/application/inspect_startup_recovery.dart';
import '../../features/managed_copy/application/managed_copy_use_case.dart';
import '../../features/managed_copy/application/repair_copy_root.dart';
import '../../features/managed_copy/data/repositories/drift_managed_copy_repository.dart';
import '../../features/managed_copy/data/services/default_operation_id_generator.dart';
import '../../features/managed_copy/data/services/managed_copy_word_converter.dart';
import '../../features/managed_copy/data/services/win32_local_file_availability_checker.dart';
import '../../features/managed_copy/domain/services/local_file_availability_checker.dart';
import '../../features/managed_copy/domain/services/word_document_converter.dart';
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
import '../../features/managed_copy/application/cleanup_recovery_artifacts.dart';
import '../../features/managed_copy/application/create_manual_backup.dart';
import '../../features/managed_copy/application/load_recovery_review.dart';
import '../../features/managed_copy/application/reconcile_managed_copy_integrity.dart';
import '../../features/managed_copy/application/run_with_verified_backup.dart';
import '../../features/managed_copy/presentation/bloc/copy_integrity_bloc.dart';
import '../../features/managed_copy/presentation/bloc/copy_settings_bloc.dart';
import '../../features/managed_copy/presentation/bloc/managed_copy_bloc.dart';
import '../../features/managed_copy/presentation/bloc/manual_backup_bloc.dart';
import '../../features/managed_copy/presentation/bloc/recovery_review_bloc.dart';
import '../../features/file_open/data/repositories/drift_file_open_repository.dart';
import '../../features/file_open/data/services/file_system_existence_checker.dart';
import '../../features/file_open/data/services/windows_os_file_opener.dart';
import '../../features/file_open/domain/repositories/file_open_repository.dart';
import '../../features/file_open/domain/services/file_existence_checker.dart';
import '../../features/file_open/domain/services/os_file_opener.dart';
import '../../features/file_open/presentation/bloc/file_open_bloc.dart';
import '../../features/reference/data/repositories/drift_reference_repository.dart';
import '../../features/reference/domain/repositories/reference_repository.dart';
import '../../features/security/application/authenticate_user.dart';
import '../../features/security/application/bootstrap_admin_account.dart';
import '../../features/security/application/change_own_password.dart';
import '../../features/security/application/record_failed_login.dart';
import '../../features/security/application/redeem_recovery_key.dart';
import '../../features/security/application/create_operator_account.dart';
import '../../features/security/application/first_login_password_change.dart';
import '../../features/security/application/issue_temporary_password.dart';
import '../../features/security/application/session_manager.dart';
import '../../features/security/application/set_initial_admin_password.dart';
import '../../features/security/application/step_up_manager.dart';
import '../../features/security/application/update_operator_account.dart';
import '../../features/security/application/verify_admin_step_up.dart';
import '../../features/security/data/repositories/drift_account_repository.dart';
import '../../features/security/data/repositories/drift_security_audit_repository.dart';
import '../../features/security/data/services/argon2id_password_hasher.dart';
import '../../features/security/domain/repositories/account_repository.dart';
import '../../features/security/domain/repositories/security_audit_repository.dart';
import '../../features/security/domain/services/password_hasher.dart';
import '../../features/security/application/load_audit_log.dart';
import '../../features/security/presentation/bloc/account_management_bloc.dart';
import '../../features/security/presentation/bloc/audit_log_bloc.dart';
import '../../features/security/presentation/bloc/initial_setup_bloc.dart';
import '../../features/security/presentation/bloc/login_bloc.dart';
import '../../features/security/presentation/bloc/password_change_bloc.dart';
import '../../features/security/presentation/bloc/recovery_bloc.dart';
import '../../features/security/presentation/bloc/step_up_bloc.dart';
import '../../features/shell/presentation/bloc/navigation_bloc.dart';
import '../../features/word_conversion/data/services/windows_microsoft_word_converter.dart';
import '../../features/word_conversion/data/services/windows_microsoft_word_probe.dart';
import '../../features/word_conversion/data/services/windows_word_output_filesystem.dart';
import '../../features/word_conversion/domain/services/microsoft_word_probe.dart';
import '../../features/word_conversion/domain/services/word_converter.dart';
import '../../features/word_conversion/domain/services/word_output_filesystem.dart';
import '../database/app_database.dart';
import '../time/clock.dart';
import '../../features/legislation/data/repositories/drift_legislation_relation_repository.dart';
import '../../features/legislation/domain/repositories/legislation_relation_repository.dart';
import '../../features/legislation/domain/usecases/create_legislation_relation.dart';
import '../../features/legislation/domain/usecases/delete_legislation_relation.dart';
import '../../features/legislation/domain/usecases/list_incoming_relations.dart';
import '../../features/legislation/domain/usecases/list_outgoing_relations.dart';
import '../../features/legislation/presentation/bloc/legislation_relation_bloc.dart';
import '../../features/related_files/application/generate_related_file_candidates_use_case.dart';
import '../../features/related_files/application/load_pending_candidates_use_case.dart';
import '../../features/related_files/application/update_candidate_status_use_case.dart';
import '../../features/related_files/data/repositories/drift_related_file_candidate_repository.dart';
import '../../features/related_files/domain/repositories/related_file_candidate_repository.dart';
import '../../features/related_files/presentation/bloc/related_review_bloc.dart';

/// Global service locator.
final GetIt getIt = GetIt.instance;

/// Registers application dependencies (M1 shell + M4 import + M5 documents + M7 file open + M8.1–M8.6 managed copy + M9.1 duplicate review + M10.1 dashboard + M11.1–M11.5 maintenance).
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
    ..registerLazySingleton<ImportJobService>(
      () => ImportJobService(
        coordinator: getIt<ImportCoordinator>(),
        protectedRootsProvider: getIt<ProtectedRootsProvider>(),
        repository: getIt<ImportRepository>(),
        clock: getIt<Clock>(),
      ),
      dispose: (s) => s.dispose(),
    )
    ..registerFactory<ImportBloc>(
      () => ImportBloc(jobService: getIt<ImportJobService>()),
    )
    ..registerFactory<ImportStatusBloc>(
      () => ImportStatusBloc(jobService: getIt<ImportJobService>()),
    )
    ..registerLazySingleton<GetRecentImportBatchesUseCase>(
      () => GetRecentImportBatchesUseCase(getIt<ImportRepository>()),
    )
    ..registerFactory<ImportHistoryBloc>(
      () => ImportHistoryBloc(
        getRecentBatches: getIt<GetRecentImportBatchesUseCase>(),
        jobSnapshots: getIt<ImportJobService>().snapshots,
      ),
    )
    ..registerLazySingleton<RelatedFileCandidateRepository>(
      () => DriftRelatedFileCandidateRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<GenerateRelatedFileCandidatesUseCase>(
      () => GenerateRelatedFileCandidatesUseCase(
        candidateRepository: getIt<RelatedFileCandidateRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerLazySingleton<LoadPendingCandidatesUseCase>(
      () =>
          LoadPendingCandidatesUseCase(getIt<RelatedFileCandidateRepository>()),
    )
    ..registerLazySingleton<UpdateCandidateStatusUseCase>(
      () => UpdateCandidateStatusUseCase(
        getIt<RelatedFileCandidateRepository>(),
        getIt<Clock>(),
      ),
    )
    ..registerFactory<RelatedReviewBloc>(
      () => RelatedReviewBloc(
        loadCandidates: getIt<LoadPendingCandidatesUseCase>(),
        updateStatus: getIt<UpdateCandidateStatusUseCase>(),
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
    // P3.1 export-eligibility foundation: transitions copied_to_library ->
    // ready_for_export.
    ..registerLazySingleton<MarkDocumentReadyForExport>(
      () => MarkDocumentReadyForExport(
        repository: getIt<DocumentMetadataRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    // P3.4.1 Review-screen export-readiness action. A fresh instance per page.
    ..registerFactory<MarkReadyForExportBloc>(
      () => MarkReadyForExportBloc(getIt<MarkDocumentReadyForExport>()),
    )
    // P3.3.1 export batch generation foundation: filesystem boundary and
    // batch repository.
    ..registerLazySingleton<ExportFilesystem>(WindowsExportFilesystem.new)
    ..registerLazySingleton<ExportBatchRepository>(
      () => DriftExportBatchRepository(getIt<AppDatabase>()),
    )
    // P3.3.2 export batch generation orchestration.
    ..registerLazySingleton<GenerateExportBatch>(
      () => GenerateExportBatch(
        metadataRepository: getIt<DocumentMetadataRepository>(),
        copyRepository: getIt<ManagedCopyRepository>(),
        batchRepository: getIt<ExportBatchRepository>(),
        filesystem: getIt<ExportFilesystem>(),
        hasher: getIt<FileHasher>(),
        clock: getIt<Clock>(),
        documentsDirectoryResolver: getIt<DocumentsDirectoryResolver>(),
      ),
    )
    // P3.4.2 Export screen. A fresh instance per page.
    ..registerLazySingleton<LoadExportScreenData>(
      () => LoadExportScreenData(
        managedCopyRepository: getIt<ManagedCopyRepository>(),
        metadataRepository: getIt<DocumentMetadataRepository>(),
        batchRepository: getIt<ExportBatchRepository>(),
      ),
    )
    ..registerFactory<ExportBatchBloc>(
      () => ExportBatchBloc(
        loadExportScreenData: getIt<LoadExportScreenData>(),
        generateExportBatch: getIt<GenerateExportBatch>(),
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
        wordConverter: getIt<WordDocumentConverter>(),
      ),
    )
    ..registerLazySingleton<ConfigureCopyRoots>(
      () => ConfigureCopyRoots(
        getIt<ManagedCopyRepository>(),
        getIt<ManagedLibraryFilesystem>(),
        getIt<PathCanonicalizer>(),
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
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
      ),
    )
    ..registerLazySingleton<InspectStartupRecovery>(
      () => InspectStartupRecovery(
        repository: getIt<ManagedCopyRepository>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
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
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
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
    // M11.1 manual database backup: use case and BLoC.
    ..registerLazySingleton<CreateManualBackup>(
      () => CreateManualBackup(
        repository: getIt<ManagedCopyRepository>(),
        backupService: getIt<DatabaseBackupService>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        operationIdGenerator: getIt<OperationIdGenerator>(),
        clock: getIt<Clock>(),
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
      ),
    )
    ..registerFactory<ManualBackupBloc>(
      () => ManualBackupBloc(getIt<CreateManualBackup>()),
    )
    ..registerFactory<CopySettingsBloc>(
      () => CopySettingsBloc(
        getIt<CopyRootPicker>(),
        getIt<ConfigureCopyRoots>(),
        getIt<InitializeCopyRoots>(),
        getIt<RepairCopyRoot>(),
        getIt<ApplyDefaultCopyRoots>(),
        getIt<ManagedCopyRepository>(),
      ),
    )
    // M11.3 recovery review: typed summary loader, safe cleanup use case, BLoC.
    ..registerLazySingleton<LoadRecoveryReview>(
      () => LoadRecoveryReview(
        repository: getIt<ManagedCopyRepository>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
      ),
    )
    ..registerLazySingleton<CleanupRecoveryArtifacts>(
      () => CleanupRecoveryArtifacts(
        repository: getIt<ManagedCopyRepository>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        inspectStartupRecovery: getIt<InspectStartupRecovery>(),
      ),
    )
    ..registerFactory<RecoveryReviewBloc>(
      () => RecoveryReviewBloc(
        getIt<LoadRecoveryReview>(),
        getIt<CleanupRecoveryArtifacts>(),
      ),
    )
    // M11.5 verified backup guard: reusable pre-operation backup enforcer.
    ..registerLazySingleton<RunWithVerifiedBackup>(
      () => RunWithVerifiedBackup(
        repository: getIt<ManagedCopyRepository>(),
        backupService: getIt<DatabaseBackupService>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        operationIdGenerator: getIt<OperationIdGenerator>(),
        clock: getIt<Clock>(),
      ),
    )
    // M11.4 managed-copy integrity reconciliation: bulk health check use case and BLoC.
    ..registerLazySingleton<ReconcileManagedCopyIntegrity>(
      () => ReconcileManagedCopyIntegrity(
        repository: getIt<ManagedCopyRepository>(),
        filesystem: getIt<ManagedLibraryFilesystem>(),
        hasher: getIt<FileHasher>(),
        operationIdGenerator: getIt<OperationIdGenerator>(),
        clock: getIt<Clock>(),
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
      ),
    )
    ..registerFactory<CopyIntegrityBloc>(
      () => CopyIntegrityBloc(getIt<ReconcileManagedCopyIntegrity>().call),
    )
    // M9.1 duplicate review: read-only repository and BLoC.
    ..registerLazySingleton<DuplicateReviewRepository>(
      () => DriftDuplicateReviewRepository(getIt<AppDatabase>()),
    )
    ..registerFactory<DuplicateReviewBloc>(
      () => DuplicateReviewBloc(repository: getIt<DuplicateReviewRepository>()),
    )
    // M10.1 dashboard: read-only Drift repository and BLoC.
    ..registerLazySingleton<DashboardRepository>(
      () => DriftDashboardRepository(getIt<AppDatabase>()),
    )
    ..registerFactory<DashboardBloc>(
      () => DashboardBloc(repository: getIt<DashboardRepository>()),
    )
    // M14.2 security: password hasher, account + audit repositories, bootstrap.
    ..registerLazySingleton<PasswordHasher>(Argon2idPasswordHasher.new)
    ..registerLazySingleton<AccountRepository>(
      () => DriftAccountRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<SecurityAuditRepository>(
      () => DriftSecurityAuditRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<BootstrapAdminAccount>(
      () => BootstrapAdminAccount(
        accounts: getIt<AccountRepository>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    // M14.3 security: session lifecycle, login, first-run admin setup.
    ..registerLazySingleton<StepUpManager>(
      StepUpManager.new,
      dispose: (m) => m.dispose(),
    )
    ..registerLazySingleton<SessionManager>(
      () => SessionManager(stepUpManager: getIt<StepUpManager>()),
      dispose: (m) => m.dispose(),
    )
    ..registerLazySingleton<RecordFailedLogin>(
      () => RecordFailedLogin(
        accounts: getIt<AccountRepository>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerLazySingleton<AuthenticateUser>(
      () => AuthenticateUser(
        accounts: getIt<AccountRepository>(),
        hasher: getIt<PasswordHasher>(),
        sessionManager: getIt<SessionManager>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
        recordFailedLogin: getIt<RecordFailedLogin>(),
      ),
    )
    ..registerLazySingleton<RedeemRecoveryKey>(
      () => RedeemRecoveryKey(
        accounts: getIt<AccountRepository>(),
        hasher: getIt<PasswordHasher>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
        sessionManager: getIt<SessionManager>(),
      ),
    )
    ..registerLazySingleton<SetInitialAdminPassword>(
      () => SetInitialAdminPassword(
        accounts: getIt<AccountRepository>(),
        hasher: getIt<PasswordHasher>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
      ),
    )
    ..registerFactory<LoginBloc>(
      () => LoginBloc(authenticateUser: getIt<AuthenticateUser>()),
    )
    ..registerFactory<InitialSetupBloc>(
      () => InitialSetupBloc(
        setInitialAdminPassword: getIt<SetInitialAdminPassword>(),
      ),
    )
    // M14.4: operator account management and password change enforcement.
    ..registerLazySingleton<CreateOperatorAccount>(
      () => CreateOperatorAccount(
        accounts: getIt<AccountRepository>(),
        hasher: getIt<PasswordHasher>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
      ),
    )
    ..registerLazySingleton<UpdateOperatorAccount>(
      () => UpdateOperatorAccount(
        accounts: getIt<AccountRepository>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
      ),
    )
    ..registerLazySingleton<IssueTemporaryPassword>(
      () => IssueTemporaryPassword(
        accounts: getIt<AccountRepository>(),
        hasher: getIt<PasswordHasher>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
      ),
    )
    ..registerLazySingleton<ChangeOwnPassword>(
      () => ChangeOwnPassword(
        accounts: getIt<AccountRepository>(),
        hasher: getIt<PasswordHasher>(),
        auditLog: getIt<SecurityAuditRepository>(),
        clock: getIt<Clock>(),
        sessionManager: getIt<SessionManager>(),
      ),
    )
    ..registerLazySingleton<FirstLoginPasswordChange>(
      () => FirstLoginPasswordChange(
        changeOwnPassword: getIt<ChangeOwnPassword>(),
        sessionManager: getIt<SessionManager>(),
      ),
    )
    ..registerFactory<AccountManagementBloc>(
      () => AccountManagementBloc(
        accounts: getIt<AccountRepository>(),
        createOperator: getIt<CreateOperatorAccount>(),
        updateOperator: getIt<UpdateOperatorAccount>(),
        issueTempPassword: getIt<IssueTemporaryPassword>(),
        sessionManager: getIt<SessionManager>(),
      ),
    )
    ..registerFactory<PasswordChangeBloc>(
      () => PasswordChangeBloc(
        firstLoginPasswordChange: getIt<FirstLoginPasswordChange>(),
      ),
    )
    ..registerFactory<RecoveryBloc>(
      () => RecoveryBloc(redeemRecoveryKey: getIt<RedeemRecoveryKey>()),
    )
    // M14.8 step-up authentication: verifier use case and dialog BLoC.
    ..registerLazySingleton<VerifyAdminStepUp>(
      () => VerifyAdminStepUp(
        accounts: getIt<AccountRepository>(),
        hasher: getIt<PasswordHasher>(),
        auditLog: getIt<SecurityAuditRepository>(),
        sessionManager: getIt<SessionManager>(),
        stepUpManager: getIt<StepUpManager>(),
      ),
    )
    ..registerFactory<StepUpBloc>(
      () => StepUpBloc(verifyAdminStepUp: getIt<VerifyAdminStepUp>()),
    )
    // M14.7 audit log viewer: admin-guarded use case + factory BLoC.
    ..registerLazySingleton<LoadAuditLog>(
      () => LoadAuditLog(
        auditLog: getIt<SecurityAuditRepository>(),
        sessionManager: getIt<SessionManager>(),
      ),
    )
    ..registerFactory<AuditLogBloc>(
      () => AuditLogBloc(loadAuditLog: getIt<LoadAuditLog>()),
    )
    // P1 Word-to-PDF conversion infrastructure. Conversion uses local
    // Microsoft Word for best Arabic document fidelity and is invoked only
    // from the managed-copy flow.
    ..registerLazySingleton<MicrosoftWordProbe>(WindowsMicrosoftWordProbe.new)
    ..registerLazySingleton<WordConverter>(WindowsMicrosoftWordConverter.new)
    ..registerLazySingleton<WordOutputFilesystem>(
      WindowsWordOutputFilesystem.new,
    )
    // Managed-copy Word converter: converts .doc sources to a temporary PDF
    // inside the managed-copy flow, without staging to the database.
    ..registerLazySingleton<LocalFileAvailabilityChecker>(
      Win32LocalFileAvailabilityChecker.new,
    )
    ..registerLazySingleton<WordDocumentConverter>(
      () => ManagedCopyWordConverter(
        probe: getIt<MicrosoftWordProbe>(),
        converter: getIt<WordConverter>(),
        outputFs: getIt<WordOutputFilesystem>(),
        hasher: getIt<FileHasher>(),
        localFileChecker: getIt<LocalFileAvailabilityChecker>(),
      ),
    )
    // Pre-P3 Slice A — legislation lifecycle + relations foundation.
    ..registerLazySingleton<LegislationRelationRepository>(
      () => DriftLegislationRelationRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<CreateLegislationRelation>(
      () => CreateLegislationRelation(getIt<LegislationRelationRepository>()),
    )
    ..registerLazySingleton<ListOutgoingRelations>(
      () => ListOutgoingRelations(getIt<LegislationRelationRepository>()),
    )
    ..registerLazySingleton<ListIncomingRelations>(
      () => ListIncomingRelations(getIt<LegislationRelationRepository>()),
    )
    ..registerLazySingleton<DeleteLegislationRelation>(
      () => DeleteLegislationRelation(getIt<LegislationRelationRepository>()),
    )
    // Pre-P3 Slice B — legislation relations BLoC (factory: one per document).
    ..registerFactory<LegislationRelationBloc>(
      () => LegislationRelationBloc(
        listOutgoing: getIt<ListOutgoingRelations>(),
        listIncoming: getIt<ListIncomingRelations>(),
        createRelation: getIt<CreateLegislationRelation>(),
        deleteRelation: getIt<DeleteLegislationRelation>(),
        clock: getIt<Clock>(),
      ),
    );
}
