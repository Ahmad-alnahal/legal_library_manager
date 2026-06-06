import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';

/// Documents screen — M1 foundation only.
///
/// Shows the page title, a search/filter visual foundation, and an empty-state
/// placeholder. No querying, filtering or data access is implemented.
class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ScreenContainer(
      children: [
        PageHeader(
          title: l10n.documentsTitle,
          subtitle: l10n.documentsSubtitle,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      hintText: l10n.documentsSearchHint,
                      prefixIcon: Icons.search_outlined,
                      enabled: false,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppSecondaryButton(
                    label: l10n.documentsFilterButton,
                    icon: Icons.filter_list_outlined,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _FilterChipPlaceholder(label: l10n.documentsFilterStatus),
                  _FilterChipPlaceholder(label: l10n.documentsFilterType),
                  _FilterChipPlaceholder(label: l10n.documentsFilterCategory),
                  _FilterChipPlaceholder(label: l10n.documentsFilterYear),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        EmptyState(
          icon: Icons.description_outlined,
          title: l10n.documentsEmptyTitle,
          message: l10n.documentsEmptyBody,
        ),
      ],
    );
  }
}

/// A non-interactive filter affordance for the M1 visual foundation.
class _FilterChipPlaceholder extends StatelessWidget {
  const _FilterChipPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      avatar: const Icon(Icons.expand_more, size: 16),
      side: const BorderSide(color: AppColors.border),
      backgroundColor: AppColors.surfaceMuted,
    );
  }
}
