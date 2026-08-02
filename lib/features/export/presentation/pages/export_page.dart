// lib/features/export/presentation/pages/export_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../domain/entities/export_batch_summary.dart';
import '../../domain/entities/generate_export_batch_result.dart';
import '../bloc/export_batch_bloc.dart';

/// The Export workspace (P3.4.2): shows the configured export root, the
/// current ready-for-export count, drives on-demand batch generation, and
/// lists prior batches. Changing the export root happens in Settings only.
class ExportPage extends StatelessWidget {
  const ExportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ExportBatchBloc>(
      create: (_) =>
          getIt<ExportBatchBloc>()..add(const ExportBatchScreenStarted()),
      child: const _ExportBody(),
    );
  }
}

class _ExportBody extends StatelessWidget {
  const _ExportBody();

  @override
  Widget build(BuildContext context) {
    return ScreenContainer(
      children: [
        const PageHeader(
          title: 'التصدير',
          subtitle: 'إنشاء حزم تصدير محلية موثقة',
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ExportRootPanel(),
        const SizedBox(height: AppSpacing.lg),
        const _ReadyForExportPanel(),
        const SizedBox(height: AppSpacing.lg),
        const _BatchHistoryPanel(),
      ],
    );
  }
}

class _ExportRootPanel extends StatelessWidget {
  const _ExportRootPanel();

  static const String _defaultLabel = r'الافتراضي: <Documents>\MARJIY\Exports';

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: BlocBuilder<ExportBatchBloc, ExportBatchState>(
        buildWhen: (p, c) => p.exportRoot != c.exportRoot,
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  const Icon(
                    Icons.outbox_outlined,
                    color: AppColors.accentTeal,
                  ),
                  Text(
                    'مجلد التصدير',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(state.exportRoot ?? _defaultLabel),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'لتغيير المجلد، انتقل إلى الإعدادات',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReadyForExportPanel extends StatelessWidget {
  const _ReadyForExportPanel();

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: BlocBuilder<ExportBatchBloc, ExportBatchState>(
        builder: (context, state) {
          final bloc = context.read<ExportBatchBloc>();
          final bool canGenerate =
              !state.isGenerating &&
              state.readyForExportCount > 0 &&
              state.loadStatus == ExportBatchLoadStatus.ready;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    color: AppColors.accentTeal,
                  ),
                  Text(
                    'جاهز للتصدير',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'عدد المستندات الجاهزة للتصدير: ${state.readyForExportCount}',
              ),
              if (state.readyForExportCount == 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'لا توجد مستندات جاهزة للتصدير حالياً. قم بتعيين المستندات '
                  'جاهزة من شاشة المراجعة.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                label: 'إنشاء حزمة تصدير',
                icon: Icons.archive_outlined,
                onPressed: canGenerate
                    ? () => bloc.add(const ExportBatchGenerateRequested())
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _GenerationStatusArea(state: state),
            ],
          );
        },
      ),
    );
  }
}

class _GenerationStatusArea extends StatelessWidget {
  const _GenerationStatusArea({required this.state});

  final ExportBatchState state;

  @override
  Widget build(BuildContext context) {
    if (state.isGenerating) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('جارٍ إنشاء حزمة التصدير...'),
        ],
      );
    }
    final String? message = _resultMessage(state.lastResult);
    if (message == null) return const SizedBox.shrink();
    return Text(message);
  }

  static String? _resultMessage(GenerateExportBatchResult? result) {
    return switch (result) {
      null => null,
      GenerateExportBatchSuccess(
        :final batchCode,
        :final includedCount,
        :final exportPath,
      ) =>
        'تم إنشاء الحزمة بنجاح: $batchCode — $includedCount مستند — المسار: '
            '$exportPath',
      GenerateExportBatchNothingToExport() => 'لا توجد مستندات جاهزة للتصدير.',
      GenerateExportBatchAllSkipped() =>
        'تعذّر تصدير جميع المستندات. تحقق من سلامة النسخ المدارة.',
      GenerateExportBatchFailed(:final exportPath) =>
        exportPath != null
            ? 'فشل إنشاء الحزمة. المجلد محفوظ للمراجعة: $exportPath'
            : 'فشل إنشاء الحزمة.',
    };
  }
}

class _BatchHistoryPanel extends StatelessWidget {
  const _BatchHistoryPanel();

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: BlocBuilder<ExportBatchBloc, ExportBatchState>(
        buildWhen: (p, c) => p.batches != c.batches,
        builder: (context, state) {
          final bloc = context.read<ExportBatchBloc>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_outlined,
                    color: AppColors.accentTeal,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'سجل حزم التصدير',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'تحديث السجل',
                    onPressed: () =>
                        bloc.add(const ExportBatchHistoryRefreshRequested()),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (state.batches.isEmpty)
                const Text('لا توجد حزم تصدير سابقة.')
              else
                for (final batch in state.batches) _BatchRow(batch: batch),
            ],
          );
        },
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch});

  final ExportBatchSummary batch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.control,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  batch.batchCode,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _StatusChip(statusKey: batch.statusKey),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${batch.documentCount} مستند — '
            '${_formatBytes(batch.totalSizeBytes)} — '
            '${_formatDate(batch.createdAt)}',
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            batch.exportPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: text.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.statusKey});

  final String statusKey;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (statusKey) {
      ExportBatchStatusKey.preparing => ('قيد الإنشاء', AppStatusColors.info),
      ExportBatchStatusKey.completed => ('مكتملة', AppStatusColors.success),
      ExportBatchStatusKey.failed => ('فاشلة', AppStatusColors.danger),
      ExportBatchStatusKey.verified => (
        'مُتحقق منها',
        AppStatusColors.success,
      ),
      ExportBatchStatusKey.uploaded => ('مرفوعة', AppStatusColors.teal),
      _ => (statusKey, AppStatusColors.neutral),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDate(DateTime dt) =>
    DateFormat('yyyy-MM-dd').format(dt.toLocal());
