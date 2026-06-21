import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../managed_copy/domain/entities/copy_roots_setup_report.dart';
import '../../../managed_copy/domain/services/copy_root_picker.dart';
import '../../../managed_copy/presentation/bloc/copy_settings_bloc.dart';
import '../../../managed_copy/presentation/bloc/manual_backup_bloc.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              getIt<CopySettingsBloc>()..add(const CopySettingsStarted()),
        ),
        BlocProvider(create: (_) => getIt<ManualBackupBloc>()),
      ],
      child: const _SettingsBody(),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MultiBlocListener(
      listeners: [
        BlocListener<CopySettingsBloc, CopySettingsState>(
          listenWhen: (a, b) =>
              a.sequence != b.sequence && b.messageKey != null,
          listener: (context, state) {
            final text = switch (state.messageKey) {
              'saved' => l10n.settingsSnackSaved,
              'choose_both' => l10n.settingsSnackChooseBoth,
              'unsafe_overlap' => l10n.settingsSnackUnsafeOverlap,
              'recreated' => l10n.settingsSnackRecreated,
              'recreate_unsafe' => l10n.settingsSnackRecreateUnsafe,
              'recreate_invalid' => l10n.settingsSnackRecreateInvalid,
              'recreate_failed' => l10n.settingsSnackRecreateFailed,
              'defaults_applied' => l10n.settingsSnackDefaultsApplied,
              'defaults_resolution_failed' =>
                l10n.settingsSnackDefaultsResolutionFailed,
              'defaults_creation_failed' =>
                l10n.settingsSnackDefaultsCreationFailed,
              _ => l10n.settingsSnackFallback,
            };
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(text)));
          },
        ),
        BlocListener<ManualBackupBloc, ManualBackupState>(
          listenWhen: (a, b) =>
              a.sequence != b.sequence && b.messageKey != null,
          listener: (context, state) {
            final text = switch (state.messageKey) {
              'success' => l10n.settingsSnackBackupSuccess,
              'not_configured' => l10n.settingsSnackBackupNotConfigured,
              'root_missing' => l10n.settingsSnackBackupRootMissing,
              _ => l10n.settingsSnackBackupFailed,
            };
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(text)));
          },
        ),
      ],
      child: ScreenContainer(
        children: [
          PageHeader(
            title: l10n.settingsTitle,
            subtitle: l10n.settingsSubtitle,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _CopyOnlyPolicyPanel(),
          const SizedBox(height: AppSpacing.lg),
          const _SettingsPanels(),
        ],
      ),
    );
  }
}

class _SettingsPanels extends StatelessWidget {
  const _SettingsPanels();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1000) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _CopyLocationsPanel()),
              SizedBox(width: AppSpacing.lg),
              SizedBox(width: 360, child: _ManualBackupPanel()),
            ],
          );
        }
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ManualBackupPanel(),
            SizedBox(height: AppSpacing.lg),
            _CopyLocationsPanel(),
          ],
        );
      },
    );
  }
}

class _CopyOnlyPolicyPanel extends StatelessWidget {
  const _CopyOnlyPolicyPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = AppStatusColors.teal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: AppRadii.card,
        border: Border.all(color: accent.foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: accent.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsCopyPolicyTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.settingsCopyPolicyBody),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.settingsCopyPolicyActive,
                  style: TextStyle(color: accent.foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyLocationsPanel extends StatelessWidget {
  const _CopyLocationsPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPanel(
      child: BlocBuilder<CopySettingsBloc, CopySettingsState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final bloc = context.read<CopySettingsBloc>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  const Icon(
                    Icons.folder_copy_outlined,
                    color: AppColors.accentTeal,
                  ),
                  Text(
                    l10n.settingsCopyLocationsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.settingsCopyLocationsBody),
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.settingsCopyLocationsWarning),
              if (state.startupRecoveryRequiresAttention) ...[
                const SizedBox(height: AppSpacing.md),
                _StartupRecoveryBanner(
                  artifactCount: state.startupRecoveryArtifactCount,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSecondaryButton(
                  label: l10n.settingsResetToDefaults,
                  icon: Icons.restore_outlined,
                  onPressed: !state.busy
                      ? () => _confirmResetToDefaults(context, bloc)
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.settingsResetWarning,
                style: const TextStyle(fontSize: 12),
              ),
              if (state.requiresAttention) ...[
                const SizedBox(height: AppSpacing.md),
                const _AttentionBanner(),
              ],
              const SizedBox(height: AppSpacing.lg),
              _LocationRow(
                title: l10n.settingsManagedRootTitle,
                value: state.managedRoot,
                status: state.managedStatus,
                icon: Icons.library_books_outlined,
                enabled: !state.busy,
                onChoose: () => _confirmAndChange(
                  context,
                  bloc,
                  CopyRootKind.managedLibrary,
                  hasCurrent: state.managedRoot != null,
                ),
                onRecreate: state.managedStatus == CopyRootStatus.missing
                    ? () => _confirmAndRecreate(
                        context,
                        bloc,
                        CopyRootKind.managedLibrary,
                      )
                    : null,
              ),
              const Divider(height: AppSpacing.xl),
              _LocationRow(
                title: l10n.settingsBackupRootTitle,
                value: state.backupRoot,
                status: state.backupStatus,
                icon: Icons.backup_outlined,
                enabled: !state.busy,
                onChoose: () => _confirmAndChange(
                  context,
                  bloc,
                  CopyRootKind.databaseBackup,
                  hasCurrent: state.backupRoot != null,
                ),
                onRecreate: state.backupStatus == CopyRootStatus.missing
                    ? () => _confirmAndRecreate(
                        context,
                        bloc,
                        CopyRootKind.databaseBackup,
                      )
                    : null,
              ),
              if (state.busy) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ManualBackupPanel extends StatelessWidget {
  const _ManualBackupPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPanel(
      child: BlocBuilder<ManualBackupBloc, ManualBackupState>(
        builder: (context, backupState) {
          final backupRootConfigured =
              context.watch<CopySettingsBloc>().state.backupRoot != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  const Icon(
                    Icons.backup_outlined,
                    color: AppColors.accentTeal,
                  ),
                  Text(
                    l10n.settingsManualBackupTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.settingsManualBackupBody),
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                label: l10n.settingsManualBackupButton,
                icon: Icons.save_outlined,
                onPressed: backupRootConfigured && !backupState.busy
                    ? () => _confirmAndBackup(context)
                    : null,
              ),
              if (backupState.busy) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }
}

Future<void> _confirmAndBackup(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final bloc = context.read<ManualBackupBloc>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.settingsManualBackupDialogTitle),
      content: Text(l10n.settingsManualBackupDialogContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.settingsDialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.settingsManualBackupDialogConfirm),
        ),
      ],
    ),
  );
  if (confirmed == true && !bloc.isClosed) {
    bloc.add(const ManualBackupRequested());
  }
}

Future<void> _confirmAndRecreate(
  BuildContext context,
  CopySettingsBloc bloc,
  CopyRootKind kind,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.settingsDialogRecreateTitle),
      content: Text(l10n.settingsDialogRecreateContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.settingsDialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.settingsDialogRecreateConfirm),
        ),
      ],
    ),
  );
  if (confirmed == true && !bloc.isClosed) {
    bloc.add(CopyRootRepairRequested(kind));
  }
}

Future<void> _confirmResetToDefaults(
  BuildContext context,
  CopySettingsBloc bloc,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.settingsDialogResetTitle),
      content: Text(l10n.settingsDialogResetContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.settingsDialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.settingsDialogResetConfirm),
        ),
      ],
    ),
  );
  if (confirmed == true && !bloc.isClosed) {
    bloc.add(const CopyRootsResetToDefaultRequested());
  }
}

Future<void> _confirmAndChange(
  BuildContext context,
  CopySettingsBloc bloc,
  CopyRootKind kind, {
  required bool hasCurrent,
}) async {
  if (!hasCurrent) {
    if (!bloc.isClosed) bloc.add(CopyRootSelectionRequested(kind));
    return;
  }
  final l10n = AppLocalizations.of(context);
  final label = kind == CopyRootKind.managedLibrary
      ? l10n.settingsManagedRootTitle
      : l10n.settingsBackupRootTitle;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.settingsDialogChangeTitle(label)),
      content: Text(l10n.settingsDialogChangeContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.settingsDialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.settingsDialogChangeContinue),
        ),
      ],
    ),
  );
  if (confirmed == true && !bloc.isClosed) {
    bloc.add(CopyRootSelectionRequested(kind));
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = AppStatusColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: AppRadii.card,
        border: Border.all(color: accent.foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, color: accent.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.settingsAttentionBannerBody,
              style: TextStyle(color: accent.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupRecoveryBanner extends StatelessWidget {
  const _StartupRecoveryBanner({required this.artifactCount});

  final int artifactCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = AppStatusColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: AppRadii.card,
        border: Border.all(color: accent.foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.pending_actions_outlined, color: accent.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.settingsStartupRecoveryAttention(artifactCount),
              style: TextStyle(color: accent.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.title,
    required this.value,
    required this.status,
    required this.icon,
    required this.enabled,
    required this.onChoose,
    this.onRecreate,
  });

  final String title;
  final String? value;
  final CopyRootStatus status;
  final IconData icon;
  final bool enabled;
  final VoidCallback onChoose;
  final VoidCallback? onRecreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(value ?? l10n.settingsLocationNotChosen),
                    const SizedBox(height: AppSpacing.xs),
                    _StatusChip(status: status),
                    if (onRecreate != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppPrimaryButton(
                          label: l10n.settingsRecreateFolder,
                          icon: Icons.create_new_folder_outlined,
                          onPressed: enabled ? onRecreate : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
          final button = AppSecondaryButton(
            label: value == null
                ? l10n.settingsChooseButton
                : l10n.settingsChangeButton,
            icon: Icons.folder_open_outlined,
            onPressed: enabled ? onChoose : null,
          );
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: button,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: AppSpacing.md),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CopyRootStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color) = switch (status) {
      CopyRootStatus.automatic => (
        l10n.settingsStatusAutomatic,
        AppStatusColors.success,
      ),
      CopyRootStatus.custom => (
        l10n.settingsStatusCustom,
        AppStatusColors.info,
      ),
      CopyRootStatus.missing => (
        l10n.settingsStatusMissing,
        AppStatusColors.warning,
      ),
      CopyRootStatus.notConfigured => (
        l10n.settingsStatusNotConfigured,
        AppStatusColors.neutral,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: AppRadii.control,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: color.foreground),
      ),
    );
  }
}
