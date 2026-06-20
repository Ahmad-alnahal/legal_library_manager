// lib/features/duplicates/presentation/pages/duplicate_review_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/safety_banner.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../documents/presentation/widgets/review_labels.dart';
import '../../domain/entities/duplicate_group_details.dart';
import '../../domain/entities/duplicate_group_file_item.dart';
import '../../domain/entities/duplicate_group_summary.dart';
import '../bloc/duplicate_review_bloc.dart';
import '../bloc/duplicate_review_event.dart';
import '../bloc/duplicate_review_state.dart';

class DuplicateReviewPage extends StatelessWidget {
  const DuplicateReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<DuplicateReviewBloc>()..add(const DuplicateReviewStarted()),
      child: BlocListener<DuplicateReviewBloc, DuplicateReviewState>(
        listenWhen: (previous, current) =>
            previous.messageKey != current.messageKey &&
            current.messageKey != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  _messageForKey(AppLocalizations.of(context), state.messageKey!),
                ),
              ),
            );
        },
        child: const _DuplicateWorkspace(),
      ),
    );
  }

  static String _messageForKey(AppLocalizations l10n, String key) =>
      switch (key) {
        'duplicate_preferred_saved' => l10n.duplicatesSnackPreferredSaved,
        'duplicate_member_hidden' => l10n.duplicatesSnackMemberHidden,
        'duplicate_member_unhidden' => l10n.duplicatesSnackMemberUnhidden,
        'duplicate_review_saved' => l10n.duplicatesSnackReviewSaved,
        'duplicate_preferred_failed' => l10n.duplicatesSnackPreferredFailed,
        'duplicate_visibility_failed' => l10n.duplicatesSnackVisibilityFailed,
        'duplicate_review_save_failed' => l10n.duplicatesSnackReviewSaveFailed,
        _ => l10n.duplicatesSnackGenericFailed,
      };
}

class _DuplicateWorkspace extends StatelessWidget {
  const _DuplicateWorkspace();

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).height < 420;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 700
                ? AppSpacing.sm
                : AppSpacing.pagePadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                PageHeader(
                  title: AppLocalizations.of(context).duplicatesTitle,
                  subtitle: AppLocalizations.of(context).duplicatesSubtitle,
                ),
                const SizedBox(height: AppSpacing.md),
                _SafetyBanner(),
                const SizedBox(height: AppSpacing.md),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 800) {
                      return const Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: _GroupListPanel()),
                          SizedBox(width: AppSpacing.md),
                          Expanded(child: _GroupDetailPanel()),
                        ],
                      );
                    }
                    // Narrow: both panels share the bounded height via Expanded
                    // so no RenderFlex can overflow at narrow/short desktop sizes.
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _GroupListPanel()),
                        SizedBox(height: AppSpacing.sm),
                        Expanded(child: _GroupDetailPanel()),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafetyBanner(
      title: l10n.duplicatesSafetyTitle,
      message: l10n.duplicatesSafetyBody,
      icon: Icons.verified_user_outlined,
      tone: SafetyBannerTone.success,
    );
  }
}

// â”€â”€â”€ Group list (left panel) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GroupListPanel extends StatefulWidget {
  const _GroupListPanel();

  @override
  State<_GroupListPanel> createState() => _GroupListPanelState();
}

class _GroupListPanelState extends State<_GroupListPanel> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    final bloc = context.read<DuplicateReviewBloc>();
    if (bloc.state.isLoadingMore || !bloc.state.hasMore) return;
    bloc.add(const DuplicateReviewNextPageRequested());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header with count and refresh
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
              vertical: AppSpacing.sm,
            ),
            child: BlocBuilder<DuplicateReviewBloc, DuplicateReviewState>(
              buildWhen: (p, c) =>
                  p.pendingReviewCount != c.pendingReviewCount ||
                  p.listStatus != c.listStatus,
              builder: (context, state) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.duplicatesGroupsLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (state.listStatus == DuplicateListStatus.success)
                      Text(
                        '${state.pendingReviewCount}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: l10n.duplicatesRetry,
                      color: AppColors.textSecondary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => context.read<DuplicateReviewBloc>().add(
                        const DuplicateReviewRefreshed(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: BlocBuilder<DuplicateReviewBloc, DuplicateReviewState>(
              builder: (context, state) => _listContent(context, state, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listContent(
    BuildContext context,
    DuplicateReviewState state,
    AppLocalizations l10n,
  ) {
    return switch (state.listStatus) {
      DuplicateListStatus.initial || DuplicateListStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      DuplicateListStatus.failure => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.duplicatesLoadError,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppStatusColors.danger.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppSecondaryButton(
                label: l10n.duplicatesRetry,
                onPressed: () => context.read<DuplicateReviewBloc>().add(
                  const DuplicateReviewRefreshed(),
                ),
              ),
            ],
          ),
        ),
      ),
      DuplicateListStatus.success =>
        state.isEmpty
            ? SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.difference_outlined,
                  title: l10n.duplicatesEmptyTitle,
                  message: l10n.duplicatesEmptyBody,
                ),
              )
            : Scrollbar(
                controller: _scrollController,
                child: ListView.separated(
                  controller: _scrollController,
                  primary: false,
                  itemCount:
                      state.groups.length + (state.isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    if (index >= state.groups.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final group = state.groups[index];
                    return _GroupTile(
                      group: group,
                      selected: state.selectedGroupId == group.id,
                    );
                  },
                ),
              ),
    };
  }
}

// ─── Review-status helpers (shared by _GroupTile and _GroupDetailsBodyState) ───

String _reviewStatusLabel(String key) => switch (key) {
  'reviewed' => 'تمت المراجعة',
  'archived_for_later' => 'مؤجلة',
  _ => 'غير مراجعة',
};

StatusColor _reviewStatusColor(String key) => switch (key) {
  'reviewed' => AppStatusColors.success,
  'archived_for_later' => AppStatusColors.warning,
  _ => AppStatusColors.neutral,
};

// â”€â”€â”€ Group tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.selected});

  final DuplicateGroupSummary group;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => context.read<DuplicateReviewBloc>().add(
        DuplicateReviewGroupSelected(group.id),
      ),
      child: ColoredBox(
        color: selected ? AppColors.navSelected : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.userLabel,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.navSelectedAccent
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  StatusChip(
                    label: _reviewStatusLabel(group.reviewStatusKey),
                    status: _reviewStatusColor(group.reviewStatusKey),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${group.groupCode} · ${group.sha256Short}',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.copy_all_outlined,
                    size: 13,
                    color: AppStatusColors.duplicate.foreground,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${group.memberCount}',
                    style: textTheme.labelSmall?.copyWith(
                      color: AppStatusColors.duplicate.foreground,
                    ),
                  ),
                  if (group.preferredFileId != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: AppStatusColors.success.foreground,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// â”€â”€â”€ Group detail (right panel) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GroupDetailPanel extends StatelessWidget {
  const _GroupDetailPanel();

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: EdgeInsets.zero,
      child: BlocBuilder<DuplicateReviewBloc, DuplicateReviewState>(
        builder: (context, state) => _content(context, state),
      ),
    );
  }

  Widget _content(BuildContext context, DuplicateReviewState state) {
    final l10n = AppLocalizations.of(context);

    if (state.selectedGroupId == null) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: EmptyState(
            icon: Icons.difference_outlined,
            title: l10n.duplicatesMembersLabel,
            message: l10n.duplicatesSelectGroupPrompt,
          ),
        ),
      );
    }

    return switch (state.detailStatus) {
      DuplicateDetailStatus.none || DuplicateDetailStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      DuplicateDetailStatus.failure => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.duplicatesLoadError,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppStatusColors.danger.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppSecondaryButton(
                label: l10n.duplicatesRetry,
                onPressed: () => context.read<DuplicateReviewBloc>().add(
                  DuplicateReviewGroupSelected(state.selectedGroupId!),
                ),
              ),
            ],
          ),
        ),
      ),
      DuplicateDetailStatus.success => _GroupDetailsBody(
        details: state.selectedDetails!,
      ),
    };
  }
}

// â”€â”€â”€ Group details body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GroupDetailsBody extends StatefulWidget {
  const _GroupDetailsBody({required this.details});

  final DuplicateGroupDetails details;

  @override
  State<_GroupDetailsBody> createState() => _GroupDetailsBodyState();
}

class _GroupDetailsBodyState extends State<_GroupDetailsBody> {
  final _scrollController = ScrollController();
  late final TextEditingController _notesController;
  late String _statusKey;

  @override
  void initState() {
    super.initState();
    _statusKey = widget.details.summary.reviewStatusKey;
    _notesController = TextEditingController(text: widget.details.notes ?? '');
  }

  @override
  void didUpdateWidget(covariant _GroupDetailsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.summary.id != widget.details.summary.id ||
        oldWidget.details.summary.reviewStatusKey !=
            widget.details.summary.reviewStatusKey ||
        oldWidget.details.notes != widget.details.notes) {
      _statusKey = widget.details.summary.reviewStatusKey;
      _notesController.text = widget.details.notes ?? '';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = widget.details.summary;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group summary header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.userLabel,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusChip(
                    label: _reviewStatusLabel(s.reviewStatusKey),
                    status: _reviewStatusColor(s.reviewStatusKey),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.groupCode,
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Text(
                    '${l10n.duplicatesSha256Label}: ',
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Flexible(
                    child: SelectableText(
                      s.sha256Hash,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.copy_all_outlined,
                    size: 13,
                    color: AppStatusColors.duplicate.foreground,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    l10n.duplicatesFileCountLabel(s.memberCount),
                    style: textTheme.labelSmall?.copyWith(
                      color: AppStatusColors.duplicate.foreground,
                    ),
                  ),
                ],
              ),
              if (widget.details.notes != null &&
                  widget.details.notes!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.details.notes!,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              BlocBuilder<DuplicateReviewBloc, DuplicateReviewState>(
                buildWhen: (p, c) => p.operation != c.operation,
                builder: (context, state) {
                  final saving =
                      state.operation == DuplicateReviewOperation.savingReview;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 210,
                            child: DropdownButtonFormField<String>(
                              initialValue: _statusKey,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l10n.duplicatesReviewStatusLabel,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'unreviewed',
                                  child: Text(_reviewStatusLabel('unreviewed')),
                                ),
                                DropdownMenuItem(
                                  value: 'reviewed',
                                  child: Text(_reviewStatusLabel('reviewed')),
                                ),
                                DropdownMenuItem(
                                  value: 'archived_for_later',
                                  child: Text(_reviewStatusLabel('archived_for_later')),
                                ),
                              ],
                              onChanged: saving
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() => _statusKey = value);
                                    },
                            ),
                          ),
                          AppPrimaryButton(
                            label: saving ? l10n.duplicatesSaving : l10n.duplicatesSaveReview,
                            icon: Icons.save_outlined,
                            onPressed: saving
                                ? null
                                : () => context.read<DuplicateReviewBloc>().add(
                                    DuplicateReviewGroupReviewSaved(
                                      groupId: s.id,
                                      statusKey: _statusKey,
                                      notes: _notesController.text,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _notesController,
                        enabled: !saving,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: l10n.duplicatesReviewNotesLabel,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            l10n.duplicatesMembersLabel,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            child: ListView.separated(
              controller: _scrollController,
              primary: false,
              itemCount: widget.details.members.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, index) => _MemberTile(
                groupId: widget.details.summary.id,
                member: widget.details.members[index],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// â”€â”€â”€ Member tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.groupId, required this.member});

  final int groupId;
  final DuplicateGroupFileItem member;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final healthColor = _healthColor(member.fileHealthKey);
    final documentTitle = member.documentTitle?.trim();
    final showDocumentTitle =
        documentTitle != null &&
        documentTitle.isNotEmpty &&
        documentTitle != member.fileName;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member.fileName,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (member.isPreferred) ...[
                const SizedBox(width: AppSpacing.xs),
                StatusChip(
                  label: l10n.duplicatesPreferredBadge,
                  status: AppStatusColors.teal,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (showDocumentTitle) ...[
            Text(
              documentTitle,
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _InfoChip(
                icon: Icons.health_and_safety_outlined,
                label: reviewFileHealthLabel(member.fileHealthKey),
                color: healthColor,
              ),
              _InfoChip(
                icon: Icons.description_outlined,
                label: reviewFileRoleLabel(member.fileRoleKey),
                color: AppStatusColors.neutral,
              ),
              if (member.isHiddenFromSearch)
                _InfoChip(
                  icon: Icons.visibility_off_outlined,
                  label: l10n.duplicatesHiddenFromSearchLabel,
                  color: AppStatusColors.warning,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (member.documentCode != null) ...[
            Text(
              '${l10n.duplicatesDocumentCode}: ${member.documentCode}',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              member.absolutePath,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              maxLines: 2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatSize(member.fileSizeBytes),
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          BlocBuilder<DuplicateReviewBloc, DuplicateReviewState>(
            buildWhen: (p, c) => p.operation != c.operation,
            builder: (context, state) {
              final busy = state.isBusy;
              return Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppSecondaryButton(
                    label: member.isPreferred
                        ? l10n.duplicatesAlreadyPreferred
                        : l10n.duplicatesSetPreferred,
                    icon: member.isPreferred
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    onPressed: busy || member.isPreferred
                        ? null
                        : () => context.read<DuplicateReviewBloc>().add(
                            DuplicateReviewPreferredMemberSet(
                              groupId: groupId,
                              fileId: member.fileId,
                            ),
                          ),
                  ),
                  AppSecondaryButton(
                    label: member.isHiddenFromSearch
                        ? l10n.duplicatesShowInSearch
                        : l10n.duplicatesHideFromSearch,
                    icon: member.isHiddenFromSearch
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    onPressed: busy
                        ? null
                        : () => context.read<DuplicateReviewBloc>().add(
                            DuplicateReviewMemberHiddenSet(
                              groupId: groupId,
                              fileId: member.fileId,
                              hidden: !member.isHiddenFromSearch,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static StatusColor _healthColor(String key) => switch (key) {
    'healthy' => AppStatusColors.success,
    'corrupted' => AppStatusColors.danger,
    'unreadable' => AppStatusColors.danger,
    'missing' => AppStatusColors.warning,
    _ => AppStatusColors.neutral,
  };

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes ب';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final StatusColor color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: AppRadii.control,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color.foreground,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
