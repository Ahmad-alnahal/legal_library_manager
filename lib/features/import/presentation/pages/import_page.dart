import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/safety_banner.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/widgets/empty_state.dart';

/// Import screen — M1 foundation only.
///
/// Shows the page title, the permanent source-file safety banner, the
/// scan-only clarification, and an empty-state placeholder. No scanning,
/// hashing or filesystem behavior is implemented here.
class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ScreenContainer(
      children: [
        PageHeader(title: l10n.importTitle, subtitle: l10n.importSubtitle),
        const SizedBox(height: AppSpacing.lg),
        SafetyBanner(
          title: l10n.sourceSafetyBannerTitle,
          message: l10n.sourceSafetyBannerBody,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.tag_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                l10n.importScanOnlyNote,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        EmptyState(
          icon: Icons.folder_off_outlined,
          title: l10n.importEmptyTitle,
          message: l10n.importEmptyBody,
        ),
      ],
    );
  }
}
