// lib/features/import/presentation/widgets/import_history_section.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/import_batch_record.dart';
import '../../domain/entities/import_batch_report.dart';
import '../bloc/import_history_bloc.dart';

/// Collapsible history panel showing recent import batches inside the Import
/// page.
///
/// Collapses automatically when [isImportActive] switches from false to true
/// so it does not distract from the active progress panel. [onReuseFolder] is
/// called with the batch source-folder string when the user taps the
/// "استيراد جديد من نفس المجلد" button on an interrupted/failed/cancelled
/// batch — the caller wires this to ImportBloc so this widget has no direct
/// dependency on ImportBloc.
class ImportHistorySection extends StatefulWidget {
  const ImportHistorySection({
    super.key,
    required this.isImportActive,
    required this.onReuseFolder,
  });

  final bool isImportActive;
  final void Function(String folder) onReuseFolder;

  @override
  State<ImportHistorySection> createState() => _ImportHistorySectionState();
}

class _ImportHistorySectionState extends State<ImportHistorySection> {
  bool _expanded = true;

  @override
  void didUpdateWidget(ImportHistorySection old) {
    super.didUpdateWidget(old);
    // Auto-collapse when the user starts a new import.
    if (!old.isImportActive && widget.isImportActive) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return BlocBuilder<ImportHistoryBloc, ImportHistoryState>(
      builder: (context, state) {
        return SectionPanel(
          title: l10n.importHistoryTitle,
          icon: Icons.history_outlined,
          trailing: IconButton(
            icon: Icon(
              _expanded
                  ? Icons.expand_less_outlined
                  : Icons.expand_more_outlined,
              size: 20,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            tooltip: _expanded ? 'طي' : 'توسيع',
          ),
          child: _expanded
              ? _buildContent(context, l10n, state)
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    ImportHistoryState state,
  ) {
    if (state.status == ImportHistoryStatus.loading ||
        state.status == ImportHistoryStatus.initial) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (state.batches.isEmpty) {
      return Text(
        l10n.importHistoryEmpty,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final List<ImportBatchRecord> batches = state.batches;
    final double height = (batches.length * 92.0).clamp(92.0, 360.0);
    return SizedBox(
      height: height,
      child: ListView.separated(
        primary: false,
        itemCount: batches.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, index) => _BatchRow(
          batch: batches[index],
          onReuseFolder: widget.onReuseFolder,
        ),
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch, required this.onReuseFolder});

  final ImportBatchRecord batch;
  final void Function(String) onReuseFolder;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool showReuseButton =
        batch.status == ImportBatchStatus.interrupted ||
        batch.status == ImportBatchStatus.failed ||
        batch.status == ImportBatchStatus.cancelled;
    final bool isInterrupted = batch.status == ImportBatchStatus.interrupted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StatusChip(
                label: _statusLabel(l10n, batch.status),
                status: _statusColor(batch.status),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _LtrText(
                  text: batch.sourceFolder,
                  style: text.bodySmall,
                ),
              ),
              if (showReuseButton)
                TextButton(
                  onPressed: () => onReuseFolder(batch.sourceFolder),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l10n.importHistoryReuseFolder,
                    style: text.bodySmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.importHistoryStartedAt(_formatDateTime(batch.startedAt)),
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.importHistorySummaryLine(
              batch.importedCount,
              batch.failedCount,
              batch.discoveredCount,
            ),
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (isInterrupted) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.importHistoryInterruptedNote,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Renders a filesystem path left-to-right inside the RTL interface.
class _LtrText extends StatelessWidget {
  const _LtrText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: TextDirection.ltr,
      style: style ?? Theme.of(context).textTheme.bodySmall,
    );
  }
}

String _formatDateTime(DateTime dt) {
  return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
}

String _statusLabel(AppLocalizations l10n, ImportBatchStatus status) {
  return switch (status) {
    ImportBatchStatus.completed => l10n.importHistoryStatusCompleted,
    ImportBatchStatus.failed => l10n.importHistoryStatusFailed,
    ImportBatchStatus.cancelled => l10n.importHistoryStatusCancelled,
    ImportBatchStatus.interrupted => l10n.importHistoryStatusInterrupted,
    ImportBatchStatus.running => l10n.importHistoryStatusCompleted,
  };
}

StatusColor _statusColor(ImportBatchStatus status) {
  return switch (status) {
    ImportBatchStatus.completed => AppStatusColors.success,
    ImportBatchStatus.failed => AppStatusColors.danger,
    ImportBatchStatus.cancelled => AppStatusColors.warning,
    ImportBatchStatus.interrupted => AppStatusColors.warning,
    ImportBatchStatus.running => AppStatusColors.neutral,
  };
}
