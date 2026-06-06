import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/safety_banner.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';

/// Duplicate Review screen — M1 foundation only.
///
/// Shows the page title, a safety explanation (metadata-only, no delete/move),
/// and an empty-state placeholder. No duplicate detection or actions exist yet.
class DuplicateReviewPage extends StatelessWidget {
  const DuplicateReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ScreenContainer(
      children: [
        PageHeader(
          title: l10n.duplicatesTitle,
          subtitle: l10n.duplicatesSubtitle,
        ),
        const SizedBox(height: AppSpacing.lg),
        SafetyBanner(
          title: l10n.duplicatesSafetyTitle,
          message: l10n.duplicatesSafetyBody,
          icon: Icons.verified_user_outlined,
          tone: SafetyBannerTone.success,
        ),
        const SizedBox(height: AppSpacing.lg),
        EmptyState(
          icon: Icons.difference_outlined,
          title: l10n.duplicatesEmptyTitle,
          message: l10n.duplicatesEmptyBody,
        ),
      ],
    );
  }
}
