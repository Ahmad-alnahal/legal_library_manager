// lib/features/related_files/presentation/widgets/related_candidate_card.dart

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/candidate_reason.dart';
import '../../domain/entities/related_file_review_row.dart';

/// Compact card for one related-file candidate pair.
///
/// Shows both files' names and paths, reason label, confidence percentage,
/// and three action buttons (confirm / reject / dismiss).
///
/// Paths are always rendered LTR to stay readable in the RTL interface.
/// All user-visible text comes from [AppLocalizations].
class RelatedCandidateCard extends StatelessWidget {
  const RelatedCandidateCard({
    super.key,
    required this.row,
    required this.onConfirm,
    required this.onReject,
    required this.onDismiss,
  });

  final RelatedFileReviewRow row;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final int pct = (row.confidence * 100).round();

    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: reason badge + confidence ─────────────────────────────
          Row(
            children: [
              _ReasonBadge(reason: row.reason, l10n: l10n),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.relatedReviewConfidencePercent(pct),
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── File A ────────────────────────────────────────────────────────
          _FileRow(
            label: l10n.relatedReviewFileA,
            name: row.fileAName,
            path: row.fileAPath,
          ),
          const SizedBox(height: AppSpacing.xs),

          // ── File B ────────────────────────────────────────────────────────
          _FileRow(
            label: l10n.relatedReviewFileB,
            name: row.fileBName,
            path: row.fileBPath,
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Actions ───────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                child: Text(l10n.relatedReviewDismiss),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: onReject,
                child: Text(l10n.relatedReviewReject),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: onConfirm,
                child: Text(l10n.relatedReviewConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _ReasonBadge extends StatelessWidget {
  const _ReasonBadge({required this.reason, required this.l10n});

  final CandidateReason reason;
  final AppLocalizations l10n;

  String _label() => switch (reason) {
    CandidateReason.docPdfPair => l10n.relatedReviewReasonDocPdf,
    CandidateReason.nearFolderBasename => l10n.relatedReviewReasonNearFolder,
    CandidateReason.titleSimilarity => l10n.relatedReviewReasonTitleSimilarity,
    CandidateReason.similarBasename => l10n.relatedReviewReasonSimilarBasename,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppStatusColors.info.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppStatusColors.info.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.label, required this.name, required this.path});

  final String label;
  final String name;
  final String path;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrap paths in LTR so Windows paths stay readable in RTL UI
              _LtrText(text: name, style: text.bodyMedium),
              _LtrText(
                text: path,
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wraps text in explicit LTR directionality so Windows paths
/// (e.g. C:\legal\…) display left-to-right inside the RTL interface.
class _LtrText extends StatelessWidget {
  const _LtrText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
