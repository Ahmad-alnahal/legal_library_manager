import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';

/// Settings screen — M1 foundation only.
///
/// Shows the page title, a prominent copy-only policy panel, and placeholder
/// settings sections with disabled safe actions. The Stitch "black canvas"
/// artifact is intentionally not reproduced, and no action is wired.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ScreenContainer(
      children: [
        PageHeader(title: l10n.settingsTitle, subtitle: l10n.settingsSubtitle),
        const SizedBox(height: AppSpacing.lg),
        _CopyOnlyPolicyPanel(l10n: l10n),
        const SizedBox(height: AppSpacing.lg),
        _SettingsSections(l10n: l10n),
      ],
    );
  }
}

class _CopyOnlyPolicyPanel extends StatelessWidget {
  const _CopyOnlyPolicyPanel({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    const StatusColor accent = AppStatusColors.teal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: AppRadii.card,
        border: Border.all(color: accent.foreground.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.policy_outlined, color: accent.foreground, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.settingsCopyPolicyTitle,
                style: text.titleMedium?.copyWith(color: accent.foreground),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.settingsCopyPolicyBody, style: text.bodyLarge),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: accent.foreground),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.settingsCopyPolicyActive,
                style: text.labelLarge?.copyWith(color: accent.foreground),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSections extends StatelessWidget {
  const _SettingsSections({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final List<Widget> sections = [
      _SettingsSection(
        icon: Icons.drive_folder_upload_outlined,
        title: l10n.settingsManagedLibraryTitle,
        body: l10n.settingsManagedLibraryBody,
        actions: [AppSecondaryButton(label: l10n.settingsActionChangeLocation)],
        note: l10n.settingsPlaceholderNote,
      ),
      _SettingsSection(
        icon: Icons.storage_outlined,
        title: l10n.settingsDatabaseTitle,
        body: l10n.settingsDatabaseBody,
        actions: [
          AppSecondaryButton(label: l10n.settingsActionChooseLocation),
          AppSecondaryButton(label: l10n.settingsActionVerifyStructure),
        ],
        note: l10n.settingsPlaceholderNote,
      ),
      _SettingsSection(
        icon: Icons.backup_outlined,
        title: l10n.settingsBackupTitle,
        body: l10n.settingsBackupBody,
        actions: const [],
        note: l10n.settingsPlaceholderNote,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool twoColumns = constraints.maxWidth >= 900;
        const double gap = AppSpacing.lg;
        final double itemWidth = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final Widget s in sections)
              SizedBox(width: itemWidth, child: s),
          ],
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
    required this.note,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  final String note;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.accentTeal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: text.bodyMedium),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(note, style: text.labelMedium),
        ],
      ),
    );
  }
}
