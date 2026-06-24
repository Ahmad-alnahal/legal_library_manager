import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/app_section.dart';

/// Presentation descriptor for a navigation destination.
class _Destination {
  const _Destination({
    required this.section,
    required this.icon,
    required this.label,
    required this.tooltip,
  });

  final AppSection section;
  final IconData icon;
  final String label;
  final String tooltip;
}

/// Right-side primary navigation for the desktop shell.
///
/// When [extended] is false the rail collapses to an icon-only strip; tooltips
/// keep every destination discoverable at narrow window widths.
class SideNavigation extends StatelessWidget {
  const SideNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    this.extended = true,
    this.showAdministration = false,
  });

  static const double extendedWidth = 248;
  static const double compactWidth = 76;

  final AppSection selected;
  final ValueChanged<AppSection> onSelected;
  final bool extended;

  /// Whether the Administration section is visible. Pass [true] only when the
  /// current session belongs to an administrator.
  final bool showAdministration;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    final List<_Destination> destinations = [
      _Destination(
        section: AppSection.dashboard,
        icon: Icons.space_dashboard_outlined,
        label: l10n.navDashboard,
        tooltip: l10n.navTooltipDashboard,
      ),
      _Destination(
        section: AppSection.import,
        icon: Icons.download_outlined,
        label: l10n.navImport,
        tooltip: l10n.navTooltipImport,
      ),
      _Destination(
        section: AppSection.documents,
        icon: Icons.description_outlined,
        label: l10n.navDocuments,
        tooltip: l10n.navTooltipDocuments,
      ),
      _Destination(
        section: AppSection.review,
        icon: Icons.fact_check_outlined,
        label: l10n.navReview,
        tooltip: l10n.navTooltipReview,
      ),
      _Destination(
        section: AppSection.categories,
        icon: Icons.account_tree_outlined,
        label: l10n.navCategories,
        tooltip: l10n.navTooltipCategories,
      ),
      _Destination(
        section: AppSection.duplicates,
        icon: Icons.difference_outlined,
        label: l10n.navDuplicates,
        tooltip: l10n.navTooltipDuplicates,
      ),
      _Destination(
        section: AppSection.settings,
        icon: Icons.settings_outlined,
        label: l10n.navSettings,
        tooltip: l10n.navTooltipSettings,
      ),
      if (showAdministration)
        _Destination(
          section: AppSection.administration,
          icon: Icons.manage_accounts_outlined,
          label: l10n.navAdministration,
          tooltip: l10n.navTooltipAdministration,
        ),
    ];

    return Container(
      width: extended ? extendedWidth : compactWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The brand header is non-essential chrome. Below this height there is
          // not enough room for both the header and the destinations, so the
          // header is dropped (never the destinations) to avoid a vertical
          // overflow during live resize, DPI changes, tests, or startup.
          final bool showHeader = constraints.maxHeight >= _headerMinHeight;

          // The destination list is always scrollable, so every destination
          // stays reachable even when vertical room is very constrained.
          final Widget navList = ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            children: [
              for (final _Destination d in destinations)
                _NavItem(
                  destination: d,
                  selected: d.section == selected,
                  extended: extended,
                  onTap: () => onSelected(d.section),
                ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHeader) ...[
                _Header(extended: extended, l10n: l10n, text: text),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
              ],
              Expanded(child: navList),
            ],
          );
        },
      ),
    );
  }

  /// Minimum rail height needed to comfortably show the brand header above the
  /// destination list; below this the header collapses.
  static const double _headerMinHeight = 360;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.extended,
    required this.l10n,
    required this.text,
  });

  final bool extended;
  final AppLocalizations l10n;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Image.asset('assets/images/logo_mark.png', width: 36, height: 36),
          if (extended) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.appTitle,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.appSubtitle,
                    style: text.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color foreground = selected
        ? AppColors.navSelectedAccent
        : AppColors.textSecondary;

    final Widget content = Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      padding: EdgeInsets.symmetric(
        horizontal: extended ? AppSpacing.md : 0,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: selected ? AppColors.navSelected : Colors.transparent,
        borderRadius: AppRadii.control,
      ),
      child: Row(
        mainAxisAlignment: extended
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Icon(destination.icon, size: 20, color: foreground),
          if (extended) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                destination.label,
                style: text.labelLarge?.copyWith(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: destination.tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.control,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}
