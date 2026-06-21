// lib/features/dashboard/presentation/pages/dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/activity_source.dart';
import '../../domain/entities/dashboard_activity_item.dart';
import '../../domain/entities/dashboard_metrics.dart';
import '../bloc/dashboard_bloc.dart';
import '../bloc/dashboard_state.dart';
import '../widgets/metric_card.dart';
import '../widgets/progress_row.dart';

/// Dashboard page: real data-backed operational metric display.
///
/// Sources: [DashboardBloc] via [DashboardRepository]. Presentation is
/// isolation-safe: no Drift, dart:io, filesystem, or process API is imported.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardBloc>(
      create: (_) => getIt<DashboardBloc>()..add(const DashboardLoad()),
      child: const _DashboardContent(),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        if (state.isLoading) {
          return ScreenContainer(
            children: [
              PageHeader(
                title: l10n.dashboardTitle,
                subtitle: l10n.dashboardSubtitle,
              ),
              const SizedBox(height: AppSpacing.lg),
              const Center(child: CircularProgressIndicator()),
            ],
          );
        }

        if (state.isFailure) {
          return ScreenContainer(
            children: [
              PageHeader(
                title: l10n.dashboardTitle,
                subtitle: l10n.dashboardSubtitle,
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 40,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.dashboardErrorMessage,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => context.read<DashboardBloc>().add(
                        const DashboardRefresh(),
                      ),
                      child: Text(l10n.dashboardRetry),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final DashboardMetrics m = state.metrics ?? DashboardMetrics.empty;

        return ScreenContainer(
          children: [
            Row(
              children: [
                Expanded(
                  child: PageHeader(
                    title: l10n.dashboardTitle,
                    subtitle: l10n.dashboardSubtitle,
                  ),
                ),
                IconButton(
                  tooltip: l10n.dashboardRefreshTooltip,
                  icon: const Icon(Icons.refresh_outlined),
                  onPressed: () => context.read<DashboardBloc>().add(
                    const DashboardRefresh(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _MetricGrid(metrics: m, l10n: l10n),
            const SizedBox(height: AppSpacing.lg),
            SectionPanel(
              title: l10n.overallProgressTitle,
              icon: Icons.insights_outlined,
              child: Column(
                children: [
                  ProgressRow(
                    label: l10n.progressClassification,
                    percent: m.classificationPercent.clamp(0.0, 1.0),
                    status: AppStatusColors.success,
                  ),
                  ProgressRow(
                    label: l10n.progressCopiedToLibrary,
                    percent: m.copiedToLibraryPercent.clamp(0.0, 1.0),
                    status: AppStatusColors.info,
                  ),
                  ProgressRow(
                    label: l10n.progressReadyForExport,
                    percent: m.readyForExportPercent.clamp(0.0, 1.0),
                    status: AppStatusColors.teal,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ActivityPanel(items: state.recentActivity, l10n: l10n),
          ],
        );
      },
    );
  }
}

// ── Metric grid ──────────────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, required this.l10n});

  static const double _minCardWidth = 220;

  final DashboardMetrics metrics;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final String Function(int) fmt = _formatCount;
    final List<_Metric> cards = [
      _Metric(
        l10n.metricTotalImported,
        fmt(metrics.totalImportedFiles),
        Icons.folder_open_outlined,
        AppStatusColors.neutral,
      ),
      _Metric(
        l10n.metricNeedsReview,
        fmt(metrics.needsReview),
        Icons.fact_check_outlined,
        AppStatusColors.warning,
      ),
      _Metric(
        l10n.metricInProgress,
        fmt(metrics.inProgress),
        Icons.pending_actions_outlined,
        AppStatusColors.info,
      ),
      _Metric(
        l10n.metricClassified,
        fmt(metrics.classified),
        Icons.verified_outlined,
        AppStatusColors.success,
      ),
      _Metric(
        l10n.metricCopiedToLibrary,
        fmt(metrics.copiedToLibrary),
        Icons.library_books_outlined,
        AppStatusColors.success,
      ),
      _Metric(
        l10n.metricReadyForExport,
        fmt(metrics.readyForExport),
        Icons.outbox_outlined,
        AppStatusColors.teal,
      ),
      _Metric(
        l10n.metricDuplicates,
        fmt(metrics.duplicateGroups),
        Icons.difference_outlined,
        AppStatusColors.duplicate,
      ),
      _Metric(
        l10n.metricCorrupted,
        fmt(metrics.corruptedFiles),
        Icons.report_gmailerrorred_outlined,
        AppStatusColors.danger,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        const double gap = AppSpacing.lg;
        final int columns = width >= 1040
            ? 4
            : width >= 720
            ? 3
            : width >= (_minCardWidth * 2 + gap)
            ? 2
            : 1;
        final double cardWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final _Metric m in cards)
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

// ── Activity panel ───────────────────────────────────────────────────────────

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.items, required this.l10n});

  final List<DashboardActivityItem> items;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SectionPanel(
      title: l10n.dashboardActivityTitle,
      icon: Icons.history_outlined,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                l10n.dashboardActivityEmpty,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            )
          : Column(
              children: [
                for (final DashboardActivityItem item in items)
                  _ActivityRow(item: item, l10n: l10n),
              ],
            ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.l10n});

  final DashboardActivityItem item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String sourceLabel = switch (item.source) {
      ActivitySource.fileOpenEvent => l10n.dashboardActivityOpenEvent,
      ActivitySource.importBatch => l10n.dashboardActivityImportBatch,
      ActivitySource.fileEvent => l10n.dashboardActivityFileEvent,
    };
    final IconData icon = switch (item.source) {
      ActivitySource.fileOpenEvent => Icons.open_in_new_outlined,
      ActivitySource.importBatch => Icons.download_outlined,
      ActivitySource.fileEvent => Icons.event_note_outlined,
    };
    final String timeLabel = _relativeTime(l10n, item.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$sourceLabel — ${item.eventKey}',
                  style: text.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.batchCode != null)
                  Text(
                    item.batchCode!,
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(timeLabel, style: text.labelSmall),
        ],
      ),
    );
  }

  static String _relativeTime(AppLocalizations l10n, DateTime ts) {
    final Duration diff = DateTime.now().toUtc().difference(ts.toUtc());
    if (diff.inDays >= 1) return l10n.dashboardRelativeDays(diff.inDays);
    if (diff.inHours >= 1) return l10n.dashboardRelativeHours(diff.inHours);
    if (diff.inMinutes >= 1) {
      return l10n.dashboardRelativeMinutes(diff.inMinutes);
    }
    return l10n.dashboardRelativeNow;
  }
}

// ── Private helpers ──────────────────────────────────────────────────────────

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.status);
  final String label;
  final String value;
  final IconData icon;
  final StatusColor status;
}

String _formatCount(int n) => NumberFormat('#,##0', 'en_US').format(n);
