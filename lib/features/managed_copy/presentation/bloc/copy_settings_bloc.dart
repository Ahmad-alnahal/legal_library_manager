import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/apply_default_copy_roots.dart';
import '../../application/configure_copy_roots.dart';
import '../../application/initialize_copy_roots.dart';
import '../../application/repair_copy_root.dart';
import '../../domain/entities/copy_roots_setup_report.dart';
import '../../domain/entities/startup_recovery_report.dart';
import '../../domain/repositories/managed_copy_repository.dart';
import '../../domain/services/copy_root_picker.dart';

sealed class CopySettingsEvent extends Equatable {
  const CopySettingsEvent();
  @override
  List<Object?> get props => [];
}

final class CopySettingsStarted extends CopySettingsEvent {
  const CopySettingsStarted();
}

final class CopyRootSelectionRequested extends CopySettingsEvent {
  const CopyRootSelectionRequested(this.kind);
  final CopyRootKind kind;
  @override
  List<Object?> get props => [kind];
}

/// Explicit user request to recreate a configured root that is missing (M8.5).
/// The presentation layer must have already obtained user confirmation.
final class CopyRootRepairRequested extends CopySettingsEvent {
  const CopyRootRepairRequested(this.kind);
  final CopyRootKind kind;
  @override
  List<Object?> get props => [kind];
}

/// Explicit user request to reset both copy roots to the MARJIY defaults
/// (M8.6 Part A). The presentation layer must have already obtained user
/// confirmation and warned that existing files are not moved.
final class CopyRootsResetToDefaultRequested extends CopySettingsEvent {
  const CopyRootsResetToDefaultRequested();
}

class CopySettingsState extends Equatable {
  const CopySettingsState({
    this.loading = true,
    this.busy = false,
    this.managedRoot,
    this.backupRoot,
    this.managedStatus = CopyRootStatus.notConfigured,
    this.backupStatus = CopyRootStatus.notConfigured,
    this.requiresAttention = false,
    this.startupRecoveryRequiresAttention = false,
    this.startupRecoveryArtifactCount = 0,
    this.messageKey,
    this.sequence = 0,
  });

  final bool loading;
  final bool busy;
  final String? managedRoot;
  final String? backupRoot;
  final CopyRootStatus managedStatus;
  final CopyRootStatus backupStatus;
  final bool requiresAttention;
  final bool startupRecoveryRequiresAttention;
  final int startupRecoveryArtifactCount;
  final String? messageKey;
  final int sequence;

  @override
  List<Object?> get props => [
    loading,
    busy,
    managedRoot,
    backupRoot,
    managedStatus,
    backupStatus,
    requiresAttention,
    startupRecoveryRequiresAttention,
    startupRecoveryArtifactCount,
    messageKey,
    sequence,
  ];
}

class CopySettingsBloc extends Bloc<CopySettingsEvent, CopySettingsState> {
  CopySettingsBloc(
    this._picker,
    this._configureRoots,
    this._initializeRoots,
    this._repairRoot,
    this._applyDefaultRoots,
    this._repository,
  ) : super(const CopySettingsState()) {
    on<CopySettingsStarted>(_onStarted);
    on<CopyRootSelectionRequested>(_onPick);
    on<CopyRootRepairRequested>(_onRepair);
    on<CopyRootsResetToDefaultRequested>(_onResetToDefault);
  }

  final CopyRootPicker _picker;
  final ConfigureCopyRoots _configureRoots;
  final InitializeCopyRoots _initializeRoots;
  final RepairCopyRoot _repairRoot;
  final ApplyDefaultCopyRoots _applyDefaultRoots;
  final ManagedCopyRepository _repository;

  Future<void> _onStarted(
    CopySettingsStarted event,
    Emitter<CopySettingsState> emit,
  ) async {
    // Idempotent: describes the configured roots, fills missing configuration
    // with safe defaults, and recreates missing default directories only.
    final report = await _initializeRoots();
    emit(await _fromReport(report));
  }

  Future<void> _onPick(
    CopyRootSelectionRequested event,
    Emitter<CopySettingsState> emit,
  ) async {
    if (state.busy) return;
    emit(_copyOf(state, busy: true));
    final selected = await _picker.pick(event.kind);
    if (selected == null) {
      emit(_copyOf(state, busy: false));
      return;
    }
    final managed = event.kind == CopyRootKind.managedLibrary
        ? selected
        : state.managedRoot;
    final backup = event.kind == CopyRootKind.databaseBackup
        ? selected
        : state.backupRoot;
    final result = await _configureRoots(managed, backup);
    final message = switch (result) {
      ConfigureCopyRootsResult.saved => 'saved',
      ConfigureCopyRootsResult.chooseBoth => 'choose_both',
      ConfigureCopyRootsResult.invalidFolder => 'invalid_folder',
      ConfigureCopyRootsResult.unsafeOverlap => 'unsafe_overlap',
      ConfigureCopyRootsResult.unauthorized => 'unauthorized',
      ConfigureCopyRootsResult.stepUpRequired => 'stepUpRequired',
    };
    if (result == ConfigureCopyRootsResult.saved) {
      // Refresh per-root statuses (automatic vs custom) from the same
      // idempotent initialization report used on startup.
      final report = await _initializeRoots();
      emit(await _fromReport(report, messageKey: message));
      return;
    }
    final keepSelection = result == ConfigureCopyRootsResult.chooseBoth;
    emit(
      CopySettingsState(
        loading: false,
        managedRoot: keepSelection ? managed : state.managedRoot,
        backupRoot: keepSelection ? backup : state.backupRoot,
        managedStatus: state.managedStatus,
        backupStatus: state.backupStatus,
        requiresAttention: state.requiresAttention,
        startupRecoveryRequiresAttention:
            state.startupRecoveryRequiresAttention,
        startupRecoveryArtifactCount: state.startupRecoveryArtifactCount,
        messageKey: message,
        sequence: state.sequence + 1,
      ),
    );
  }

  Future<void> _onRepair(
    CopyRootRepairRequested event,
    Emitter<CopySettingsState> emit,
  ) async {
    if (state.busy) return;
    emit(_copyOf(state, busy: true));

    final result = await _repairRoot(event.kind);

    // Success (or the folder already existing) refreshes Settings state from the
    // same idempotent initialization report; a now-present root drops back to
    // automatic/custom and the re-create action disappears.
    if (result == RepairCopyRootResult.repaired ||
        result == RepairCopyRootResult.alreadyExists) {
      final report = await _initializeRoots();
      emit(await _fromReport(report, messageKey: 'recreated'));
      return;
    }

    // Failure keeps the requires-attention state untouched and surfaces a safe
    // message; managed-copy actions remain blocked.
    final String messageKey = switch (result) {
      RepairCopyRootResult.unsafeOverlap => 'recreate_unsafe',
      RepairCopyRootResult.invalidPath => 'recreate_invalid',
      _ => 'recreate_failed',
    };
    emit(
      CopySettingsState(
        loading: false,
        managedRoot: state.managedRoot,
        backupRoot: state.backupRoot,
        managedStatus: state.managedStatus,
        backupStatus: state.backupStatus,
        requiresAttention: state.requiresAttention,
        startupRecoveryRequiresAttention:
            state.startupRecoveryRequiresAttention,
        startupRecoveryArtifactCount: state.startupRecoveryArtifactCount,
        messageKey: messageKey,
        sequence: state.sequence + 1,
      ),
    );
  }

  Future<void> _onResetToDefault(
    CopyRootsResetToDefaultRequested event,
    Emitter<CopySettingsState> emit,
  ) async {
    if (state.busy) return;
    emit(_copyOf(state, busy: true));

    final result = await _applyDefaultRoots();

    if (result == ApplyDefaultCopyRootsResult.applied) {
      // Refresh per-root statuses from the initialization report so both roots
      // are shown as automatic.
      final report = await _initializeRoots();
      emit(await _fromReport(report, messageKey: 'defaults_applied'));
      return;
    }

    final String messageKey = switch (result) {
      ApplyDefaultCopyRootsResult.documentsNotResolvable =>
        'defaults_resolution_failed',
      ApplyDefaultCopyRootsResult.directoryCreationFailed =>
        'defaults_creation_failed',
      ApplyDefaultCopyRootsResult.unsafeOverlap => 'unsafe_overlap',
      ApplyDefaultCopyRootsResult.unauthorized => 'unauthorized',
      ApplyDefaultCopyRootsResult.stepUpRequired => 'stepUpRequired',
      _ => 'invalid_folder',
    };
    emit(
      CopySettingsState(
        loading: false,
        managedRoot: state.managedRoot,
        backupRoot: state.backupRoot,
        managedStatus: state.managedStatus,
        backupStatus: state.backupStatus,
        requiresAttention: state.requiresAttention,
        startupRecoveryRequiresAttention:
            state.startupRecoveryRequiresAttention,
        startupRecoveryArtifactCount: state.startupRecoveryArtifactCount,
        messageKey: messageKey,
        sequence: state.sequence + 1,
      ),
    );
  }

  Future<CopySettingsState> _fromReport(
    CopyRootsSetupReport report, {
    String? messageKey,
  }) async {
    final StartupRecoveryReport recovery = await _repository
        .loadStartupRecoveryReport();
    return CopySettingsState(
      loading: false,
      managedRoot: report.managedRoot,
      backupRoot: report.backupRoot,
      managedStatus: report.managedStatus,
      backupStatus: report.backupStatus,
      requiresAttention: report.requiresAttention,
      startupRecoveryRequiresAttention: recovery.requiresAttention,
      startupRecoveryArtifactCount: recovery.artifactCount,
      messageKey: messageKey,
      sequence: messageKey == null ? state.sequence : state.sequence + 1,
    );
  }

  CopySettingsState _copyOf(CopySettingsState source, {required bool busy}) {
    return CopySettingsState(
      loading: false,
      busy: busy,
      managedRoot: source.managedRoot,
      backupRoot: source.backupRoot,
      managedStatus: source.managedStatus,
      backupStatus: source.backupStatus,
      requiresAttention: source.requiresAttention,
      startupRecoveryRequiresAttention: source.startupRecoveryRequiresAttention,
      startupRecoveryArtifactCount: source.startupRecoveryArtifactCount,
      sequence: source.sequence,
    );
  }
}
