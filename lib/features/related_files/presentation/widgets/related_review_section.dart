// lib/features/related_files/presentation/widgets/related_review_section.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../l10n/app_localizations.dart';
import '../bloc/related_review_bloc.dart';
import 'related_candidate_card.dart';

/// Collapsible section that shows pending related-file candidates.
///
/// Placed below [ImportHistorySection] in [ImportView]. Uses
/// [BlocConsumer<RelatedReviewBloc, RelatedReviewState>] — the bloc must be
/// provided above this widget in the tree (wired in [ImportPage]).
class RelatedReviewSection extends StatefulWidget {
  const RelatedReviewSection({super.key});

  @override
  State<RelatedReviewSection> createState() => _RelatedReviewSectionState();
}

class _RelatedReviewSectionState extends State<RelatedReviewSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<RelatedReviewBloc, RelatedReviewState>(
      listenWhen: (prev, curr) => !prev.actionError && curr.actionError,
      listener: (context, state) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.relatedReviewActionError)));
      },
      builder: (context, state) {
        final count = state.rows.length;
        return SectionPanel(
          title: l10n.relatedReviewTitle,
          icon: Icons.link_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count > 0) _CountBadge(count: count, l10n: l10n),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                tooltip: _expanded ? 'طي' : 'توسيع',
              ),
            ],
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
    RelatedReviewState state,
  ) {
    if (state.status == RelatedReviewStatus.loading ||
        state.status == RelatedReviewStatus.initial) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    if (state.status == RelatedReviewStatus.failure) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          l10n.relatedReviewLoadError,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    if (state.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          l10n.relatedReviewEmpty,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return SizedBox(
      // Height scales with count (one card ≈ 172 px) but capped at 600 px.
      height: (state.rows.length * 172.0).clamp(172.0, 600.0),
      child: ListView.separated(
        primary: false,
        itemCount: state.rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final row = state.rows[index];
          return RelatedCandidateCard(
            key: ValueKey(row.candidateId),
            row: row,
            onConfirm: () => context.read<RelatedReviewBloc>().add(
              RelatedReviewConfirmRequested(candidateId: row.candidateId),
            ),
            onReject: () => context.read<RelatedReviewBloc>().add(
              RelatedReviewRejectRequested(candidateId: row.candidateId),
            ),
            onDismiss: () => context.read<RelatedReviewBloc>().add(
              RelatedReviewDismissRequested(candidateId: row.candidateId),
            ),
          );
        },
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.l10n});

  final int count;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        l10n.relatedReviewCount(count),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
