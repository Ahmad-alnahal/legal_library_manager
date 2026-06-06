import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/metric_card.dart';
import '../widgets/progress_row.dart';

/// Dashboard: a static operational metric layout inspired by UI-v3.
///
/// Numbers are fixed design placeholders; no data is loaded in M1.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final List<_Metric> metrics = [
      _Metric(
        l10n.metricTotalImported,
        '23,450',
        Icons.folder_open_outlined,
        AppStatusColors.neutral,
      ),
      _Metric(
        l10n.metricNeedsReview,
        '432',
        Icons.fact_check_outlined,
        AppStatusColors.warning,
      ),
      _Metric(
        l10n.metricInProgress,
        '1,204',
        Icons.pending_actions_outlined,
        AppStatusColors.info,
      ),
      _Metric(
        l10n.metricClassified,
        '18,500',
        Icons.verified_outlined,
        AppStatusColors.success,
      ),
      _Metric(
        l10n.metricCopiedToLibrary,
        '15,200',
        Icons.library_books_outlined,
        AppStatusColors.success,
      ),
      _Metric(
        l10n.metricReadyForExport,
        '2,800',
        Icons.outbox_outlined,
        AppStatusColors.teal,
      ),
      _Metric(
        l10n.metricDuplicates,
        '412',
        Icons.difference_outlined,
        AppStatusColors.duplicate,
      ),
      _Metric(
        l10n.metricCorrupted,
        '89',
        Icons.report_gmailerrorred_outlined,
        AppStatusColors.danger,
      ),
    ];

    return ScreenContainer(
      children: [
        PageHeader(
          title: l10n.dashboardTitle,
          subtitle: l10n.dashboardSubtitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            const Icon(
              Icons.info_outline,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                l10n.dashboardStaticNotice,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _MetricGrid(metrics: metrics),
        const SizedBox(height: AppSpacing.lg),
        SectionPanel(
          title: l10n.overallProgressTitle,
          icon: Icons.insights_outlined,
          child: Column(
            children: [
              ProgressRow(
                label: l10n.progressClassification,
                percent: 0.78,
                status: AppStatusColors.success,
              ),
              ProgressRow(
                label: l10n.progressCopiedToLibrary,
                percent: 0.65,
                status: AppStatusColors.info,
              ),
              ProgressRow(
                label: l10n.progressReadyForExport,
                percent: 0.12,
                status: AppStatusColors.teal,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.status);
  final String label;
  final String value;
  final IconData icon;
  final StatusColor status;
}

/// Responsive metric grid: 4 columns on wide windows, fewer when narrow.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final int columns = width >= 1040
            ? 4
            : width >= 720
            ? 3
            : 2;
        const double gap = AppSpacing.lg;
        final double cardWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final _Metric m in metrics)
              SizedBox(
                width: cardWidth,
                child: MetricCard(
                  label: m.label,
                  value: m.value,
                  icon: m.icon,
                  status: m.status,
                ),
              ),
          ],
        );
      },
    );
  }
}
