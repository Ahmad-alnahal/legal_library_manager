import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/validation/validation_error.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../categories/domain/repositories/category_management_repository.dart';
import '../../../export/presentation/bloc/mark_ready_for_export_bloc.dart';
import '../../../export/presentation/widgets/mark_ready_for_export_feedback.dart';
import '../../../file_open/domain/entities/file_health_eligibility.dart';
import '../../../file_open/presentation/bloc/file_open_bloc.dart';
import '../../../file_open/presentation/widgets/file_open_feedback.dart';
import '../../../file_open/presentation/widgets/open_actions.dart';
import '../../../managed_copy/presentation/bloc/managed_copy_bloc.dart';
import '../../../managed_copy/presentation/widgets/managed_copy_feedback.dart';
import '../../../reference/domain/repositories/reference_repository.dart';
import '../../domain/entities/document_aggregate.dart';
import '../../domain/entities/document_classification_input.dart';
import '../../domain/entities/document_common_metadata.dart';
import '../../domain/entities/document_list_item.dart';
import '../../domain/entities/document_type_details.dart';
import '../../domain/entities/draft_save_input.dart';
import '../../domain/entities/keyword_input.dart';
import '../../domain/entities/review_queue_item.dart';
import '../../domain/entities/review_queue_query.dart';
import '../../domain/repositories/document_list_repository.dart';
import '../../../legislation/presentation/widgets/legislation_relations_section.dart';
import '../bloc/review_bloc.dart';
import '../bloc/review_event.dart';
import '../bloc/review_state.dart';
import '../widgets/review_labels.dart';

/// The Document Review / Classification workspace (M6.2).
///
/// A three-panel Arabic RTL workstation built on the M6.1 [ReviewBloc]: a review
/// queue, a read-only source-information panel, and an editable metadata /
/// classification form. No filesystem actions are exposed.
class DocumentReviewPage extends StatelessWidget {
  const DocumentReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ReviewBloc>(
          create: (_) => getIt<ReviewBloc>()..add(const ReviewStarted()),
        ),
        BlocProvider<FileOpenBloc>(create: (_) => getIt<FileOpenBloc>()),
        BlocProvider<ManagedCopyBloc>(create: (_) => getIt<ManagedCopyBloc>()),
        BlocProvider<MarkReadyForExportBloc>(
          create: (_) => getIt<MarkReadyForExportBloc>(),
        ),
      ],
      child: FileOpenFeedbackListener(
        child: Builder(
          builder: (context) => ManagedCopyFeedbackListener(
            onSuccess: () =>
                context.read<ReviewBloc>().add(const ReviewRefreshRequested()),
            child: MarkReadyForExportFeedbackListener(
              onSuccess: () => context.read<ReviewBloc>().add(
                const ReviewRefreshRequested(),
              ),
              child: _ReviewWorkspace(
                references: getIt<ReferenceRepository>(),
                categories: getIt<CategoryManagementRepository>(),
                documents: getIt<DocumentListRepository>(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewWorkspace extends StatefulWidget {
  const _ReviewWorkspace({
    required this.references,
    required this.categories,
    required this.documents,
  });

  final ReferenceRepository references;
  final CategoryManagementRepository categories;
  final DocumentListRepository documents;

  @override
  State<_ReviewWorkspace> createState() => _ReviewWorkspaceState();
}

class _ReviewWorkspaceState extends State<_ReviewWorkspace> {
  late final Future<ReviewReferences> _references;

  @override
  void initState() {
    super.initState();
    _references = ReviewReferences.load(widget.references, widget.categories);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReviewReferences>(
      future: _references,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.pagePadding),
            child: AppPanel(
              borderColor: Color(0xFFF3B5B5),
              child: Text('تعذّر تحميل البيانات المرجعية للتصنيف.'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _ReviewBody(
          references: snapshot.requireData,
          documents: widget.documents,
        );
      },
    );
  }
}

class _ReviewBody extends StatefulWidget {
  const _ReviewBody({required this.references, required this.documents});

  final ReviewReferences references;
  final DocumentListRepository documents;

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  ReviewState? _previous;
  bool _confirmDialogOpen = false;

  void _onState(BuildContext context, ReviewState state) {
    final prev = _previous;
    _previous = state;

    // Unsaved-change confirmation before discarding edits on selection change.
    if (state.requiresSelectionConfirmation &&
        (prev == null || !prev.requiresSelectionConfirmation) &&
        !_confirmDialogOpen) {
      _showDiscardDialog(context);
    }

    if (prev == null) return;

    // Operation success feedback (no validation errors, no failure key).
    if (prev.operation != ReviewOperation.none &&
        state.operation == ReviewOperation.none &&
        state.validationErrors.isEmpty &&
        state.operationErrorKey == null) {
      final message = switch (prev.operation) {
        ReviewOperation.saving => 'تم حفظ المسودة.',
        ReviewOperation.approving => 'تم اعتماد التصنيف.',
        ReviewOperation.returning => 'أُعيد المستند إلى قيد التصنيف.',
        ReviewOperation.none => null,
      };
      if (message != null) _snack(context, message);
    }

    // Operation failure feedback (safe internal key, never raw details).
    if (state.operationErrorKey != null &&
        prev.operationErrorKey != state.operationErrorKey) {
      _snack(context, 'تعذّر إكمال العملية. لم تتأثر الملفات الأصلية.');
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDiscardDialog(BuildContext context) async {
    _confirmDialogOpen = true;
    final bloc = context.read<ReviewBloc>();
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديلات غير محفوظة'),
        content: const Text(
          'لديك تعديلات لم تُحفظ على المستند الحالي. هل تريد تجاهلها والانتقال '
          'إلى المستند الآخر؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('البقاء والتعديل'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تجاهل والانتقال'),
          ),
        ],
      ),
    );
    _confirmDialogOpen = false;
    if (discard == true) {
      bloc.add(const ReviewSelectionChangeConfirmed());
    } else {
      bloc.add(const ReviewSelectionChangeCancelled());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool compactHeight = MediaQuery.sizeOf(context).height < 420;
    return BlocListener<ReviewBloc, ReviewState>(
      listener: _onState,
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 700
              ? AppSpacing.sm
              : AppSpacing.pagePadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compactHeight)
              const PageHeader(
                title: 'مراجعة وتصنيف المستندات',
                subtitle:
                    'راجع المستندات المستوردة وصنّفها. تبقى الملفات الأصلية '
                    'للقراءة فقط ولا يجري أي نقل أو نسخ أو حذف.',
              ),
            if (!compactHeight) const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Three side-by-side panels when wide enough; otherwise a
                  // single vertical scroll with intrinsic-height panels so no
                  // RenderFlex can overflow at narrow/short desktop sizes.
                  if (constraints.maxWidth >= 1000) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 300,
                          child: _QueuePanel(references: widget.references),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 4,
                          child: _SourcePanel(
                            fill: true,
                            documents: widget.documents,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 6,
                          child: _MetadataForm(
                            fill: true,
                            references: widget.references,
                          ),
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 280,
                          child: _QueuePanel(references: widget.references),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _SourcePanel(fill: false, documents: widget.documents),
                        const SizedBox(height: AppSpacing.md),
                        _MetadataForm(
                          fill: false,
                          references: widget.references,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Queue panel
// --------------------------------------------------------------------------

class _QueuePanel extends StatefulWidget {
  const _QueuePanel({required this.references});

  final ReviewReferences references;

  @override
  State<_QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<_QueuePanel> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 200) {
      context.read<ReviewBloc>().add(const ReviewNextPageRequested());
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: BlocBuilder<ReviewBloc, ReviewState>(
        buildWhen: (p, c) =>
            p.scope != c.scope ||
            p.queueStatus != c.queueStatus ||
            p.queueItems != c.queueItems ||
            p.queueTotalCount != c.queueTotalCount ||
            p.isLoadingMoreQueue != c.isLoadingMoreQueue ||
            p.queueErrorKey != c.queueErrorKey ||
            p.selectedDocumentId != c.selectedDocumentId,
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'قائمة المراجعة',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              _ScopeSelector(scope: state.scope),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'الإجمالي: ${state.queueTotalCount} | المعروض: '
                '${state.queueItems.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: _queueContent(context, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _queueContent(BuildContext context, ReviewState state) {
    switch (state.queueStatus) {
      case ReviewQueueStatus.initial:
      case ReviewQueueStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ReviewQueueStatus.failure:
        return const _QueueError();
      case ReviewQueueStatus.success:
        if (state.queueItems.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'لا توجد مستندات في هذه القائمة.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          controller: _scrollController,
          primary: false,
          itemCount:
              state.queueItems.length + (state.isLoadingMoreQueue ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            if (index >= state.queueItems.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = state.queueItems[index];
            return _QueueTile(
              item: item,
              selected: item.id == state.selectedDocumentId,
            );
          },
        );
    }
  }
}

/// A compact, professional two-option queue-scope selector. Deliberately a
/// rectangular segmented control with a modest 6px corner radius (never a
/// pill/stadium/oval shape) so it sits cleanly under the queue title even in a
/// narrow panel. The selected option uses a restrained MARJIY navy-on-light-blue
/// treatment; the unselected option stays clearly clickable. At extremely narrow
/// widths the two options stack vertically rather than overflow. Queue-scope
/// behavior and [ReviewBloc] events are unchanged.
class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.scope});

  final ReviewQueueScope scope;

  static const double _stackBelowWidth = 220;

  void _select(BuildContext context, ReviewQueueScope value) {
    if (value == scope) return;
    context.read<ReviewBloc>().add(ReviewQueueScopeChanged(value));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final segments = [
          _ScopeSegment(
            label: 'قيد المراجعة',
            selected: scope == ReviewQueueScope.reviewQueue,
            onTap: () => _select(context, ReviewQueueScope.reviewQueue),
          ),
          _ScopeSegment(
            label: 'المصنّفة',
            selected: scope == ReviewQueueScope.classified,
            onTap: () => _select(context, ReviewQueueScope.classified),
          ),
        ];
        final bool stacked = constraints.maxWidth < _stackBelowWidth;
        return Container(
          key: const Key('review_scope_selector'),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadii.control,
            border: Border.all(color: AppColors.border),
          ),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    segments[0],
                    const SizedBox(height: 2),
                    segments[1],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: segments[0]),
                    const SizedBox(width: 2),
                    Expanded(child: segments[1]),
                  ],
                ),
        );
      },
    );
  }
}

class _ScopeSegment extends StatelessWidget {
  const _ScopeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppColors.navSelected : AppColors.surface,
      borderRadius: AppRadii.control,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.control,
            border: Border.all(
              color: selected
                  ? AppColors.navSelectedAccent
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.item, required this.selected});

  final ReviewQueueItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = _queueTitle(item);
    return Material(
      color: selected ? AppColors.navSelected : AppColors.surfaceMuted,
      borderRadius: AppRadii.control,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('review_queue_tile_${item.id}'),
        onTap: () =>
            context.read<ReviewBloc>().add(ReviewDocumentSelected(item.id)),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadii.control,
            border: Border.all(
              color: selected ? AppColors.navSelectedAccent : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.documentCode ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall,
                    ),
                  ),
                  StatusChip(
                    label: reviewWorkflowLabel(item.workflowStatusKey),
                    status: _workflowColor(item.workflowStatusKey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueError extends StatelessWidget {
  const _QueueError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'تعذّر تحميل قائمة المراجعة.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppSecondaryButton(
            label: 'إعادة المحاولة',
            icon: Icons.refresh,
            onPressed: () =>
                context.read<ReviewBloc>().add(const ReviewRetryRequested()),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Source information panel (read-only)
// --------------------------------------------------------------------------

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({required this.fill, required this.documents});

  /// When true the panel fills its (bounded) height and scrolls internally;
  /// when false it sizes to content for an outer scroll view.
  final bool fill;
  final DocumentListRepository documents;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewBloc, ReviewState>(
      buildWhen: (p, c) =>
          p.selectedDocumentId != c.selectedDocumentId ||
          p.documentStatus != c.documentStatus ||
          p.aggregate != c.aggregate,
      builder: (context, state) {
        return AppPanel(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: AppColors.accentTeal,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'معلومات الملف المصدري',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _area(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _area(BuildContext context, ReviewState state) {
    final aggregate = state.aggregate;
    final id = state.selectedDocumentId;
    Widget content;
    if (state.documentStatus == ReviewDocumentStatus.loaded &&
        aggregate != null &&
        id != null) {
      final view = _SourceFilesView(
        key: ValueKey(id),
        documentId: id,
        aggregate: aggregate,
        documents: documents,
      );
      return fill ? Expanded(child: SingleChildScrollView(child: view)) : view;
    }
    content = switch (state.documentStatus) {
      ReviewDocumentStatus.loading => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      ),
      ReviewDocumentStatus.notFound => const SizedBox(
        height: 160,
        child: Center(child: Text('المستند غير موجود.')),
      ),
      ReviewDocumentStatus.failure => const SizedBox(
        height: 160,
        child: _DocumentError(),
      ),
      _ => const SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'اختر مستندًا من القائمة لعرض ملفاته المصدرية.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    };
    return fill ? Expanded(child: content) : content;
  }
}

class _SourceFilesView extends StatefulWidget {
  const _SourceFilesView({
    super.key,
    required this.documentId,
    required this.aggregate,
    required this.documents,
  });

  final int documentId;
  final DocumentAggregate aggregate;
  final DocumentListRepository documents;

  @override
  State<_SourceFilesView> createState() => _SourceFilesViewState();
}

class _SourceFilesViewState extends State<_SourceFilesView> {
  late Future<List<DocumentSourceFileItem>> _files;

  @override
  void initState() {
    super.initState();
    _files = widget.documents.getSourceFiles(widget.documentId);
  }

  @override
  void didUpdateWidget(covariant _SourceFilesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aggregate != widget.aggregate) {
      _files = widget.documents.getSourceFiles(widget.documentId);
    }
  }

  Future<void> _setPreferred(DocumentSourceFileItem file) async {
    try {
      await widget.documents.setPreferredSourceFile(widget.documentId, file.id);
      if (!mounted) return;
      setState(() {
        _files = widget.documents.getSourceFiles(widget.documentId);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('تم تعيين ${file.fileName} كمصدر مفضل.')),
        );
    } catch (e) {
      if (!mounted) return;
      debugPrint('setPreferredSourceFile failed: $e');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تعذّر تعيين الملف كمصدر مفضل بأمان.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final aggregate = widget.aggregate;
    final convertedHealthy = aggregate.files.where(
      (f) => f.fileRoleKey == 'converted_pdf',
    );
    final hasMissingManagedCopy = aggregate.files.any(
      (f) => f.fileRoleKey == 'managed_copy' && f.fileHealthKey == 'missing',
    );
    final hasHealthyManagedCopy = aggregate.files.any(
      (f) =>
          f.fileRoleKey == 'managed_copy' &&
          canOpenFileDirectly(f.fileHealthKey),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppStatusColors.info.background,
            borderRadius: AppRadii.control,
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'الملفات الأصلية للقراءة فقط ولا يجري عليها أي تعديل.',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'الحالة: ${reviewWorkflowLabel(aggregate.workflowStatusKey)}',
          style: text.labelLarge,
        ),
        if (aggregate.documentCode != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text('الرمز: ${aggregate.documentCode}'),
          ),
        if (hasMissingManagedCopy && !hasHealthyManagedCopy) ...[
          const SizedBox(height: AppSpacing.sm),
          const _MissingManagedCopyWarning(),
        ],
        const SizedBox(height: AppSpacing.md),
        FutureBuilder<List<DocumentSourceFileItem>>(
          future: _files,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('تعذّر تحميل تفاصيل الملفات المصدرية.');
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final files = snapshot.requireData;
            if (files.isEmpty) {
              return const Text('لا توجد ملفات مصدرية مسجلة لهذا المستند.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الملفات المصدرية', style: text.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                ...files.map(
                  (file) => _SourceFileCard(
                    file: file,
                    onSetPreferred:
                        canOpenFileDirectly(file.fileHealthKey) &&
                            file.absolutePath.toLowerCase().endsWith('.pdf')
                        ? () => _setPreferred(file)
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
        if (convertedHealthy.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('ملفات PDF المحوّلة', style: text.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          ...convertedHealthy.map(
            (f) => Text(
              '• ${reviewFileHealthLabel(f.fileHealthKey)}',
              style: text.bodySmall,
            ),
          ),
        ],
        if (aggregate.conversions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('حالة التحويل', style: text.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          ...aggregate.conversions.map(
            (c) => Text(
              '• ${reviewConversionStatusLabel(c.statusKey)}',
              style: text.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// Shown in the source-information panel when a managed-copy file record exists
/// in the database but the physical PDF is no longer present on disk (M8.6).
///
/// Displayed after reconciliation has downgraded the document to 'classified',
/// informing the user that re-copy is now available.
class _MissingManagedCopyWarning extends StatelessWidget {
  const _MissingManagedCopyWarning();

  @override
  Widget build(BuildContext context) {
    const accent = AppStatusColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: AppRadii.control,
        border: Border.all(color: accent.foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: accent.foreground,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'النسخة المدارة مفقودة. يمكن إعادة النسخ بعد التحقق.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: accent.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceFileCard extends StatelessWidget {
  const _SourceFileCard({required this.file, this.onSetPreferred});

  final DocumentSourceFileItem file;
  final VoidCallback? onSetPreferred;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            file.fileName,
            textDirection: TextDirection.ltr,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('المسار الكامل:', style: text.labelSmall),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SelectableText(
              file.absolutePath,
              textDirection: TextDirection.ltr,
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _Tag(reviewFileRoleLabel(file.fileRoleKey)),
              _Tag(reviewFileHealthLabel(file.fileHealthKey)),
              _Tag(_formatBytes(file.fileSizeBytes)),
              _Tag(file.isReadOnlySource ? 'مصدر للقراءة فقط' : 'نسخة مُدارة'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          OpenActions(
            fileId: file.id,
            showOpenFile: canOpenFileDirectly(file.fileHealthKey),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: file.isPreferred
                ? StatusChip(
                    label: 'المصدر المفضل',
                    status: AppStatusColors.success,
                  )
                : AppSecondaryButton(
                    label: 'تعيين كمصدر مفضل',
                    icon: Icons.star_outline,
                    onPressed: onSetPreferred,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.control,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _DocumentError extends StatelessWidget {
  const _DocumentError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('تعذّر تحميل المستند.'),
          const SizedBox(height: AppSpacing.sm),
          AppSecondaryButton(
            label: 'إعادة المحاولة',
            icon: Icons.refresh,
            onPressed: () =>
                context.read<ReviewBloc>().add(const ReviewRetryRequested()),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Metadata + classification form
// --------------------------------------------------------------------------

class _MetadataForm extends StatelessWidget {
  const _MetadataForm({required this.fill, required this.references});

  /// When true the form fills its (bounded) height and scrolls internally;
  /// when false it sizes to content for an outer scroll view.
  final bool fill;
  final ReviewReferences references;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: BlocBuilder<ReviewBloc, ReviewState>(
        buildWhen: (p, c) =>
            p.selectedDocumentId != c.selectedDocumentId ||
            p.documentStatus != c.documentStatus ||
            p.validationErrors != c.validationErrors ||
            p.aggregate != c.aggregate,
        builder: (context, state) {
          if (state.documentStatus == ReviewDocumentStatus.none) {
            return const EmptyState(
              icon: Icons.fact_check_outlined,
              title: 'لم يُحدد مستند',
              message: 'اختر مستندًا من قائمة المراجعة لبدء التصنيف.',
            );
          }
          if (state.documentStatus == ReviewDocumentStatus.loading) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.documentStatus == ReviewDocumentStatus.notFound) {
            return const SizedBox(
              height: 200,
              child: Center(child: Text('المستند غير موجود.')),
            );
          }
          if (state.documentStatus == ReviewDocumentStatus.failure) {
            return const SizedBox(height: 200, child: _DocumentError());
          }
          final draft = state.draft;
          final id = state.selectedDocumentId;
          if (draft == null || id == null) return const SizedBox.shrink();
          final fields = _FormFields(
            key: ValueKey(id),
            initialDraft: draft,
            references: references,
            validationErrors: state.validationErrors,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (fill)
                Expanded(child: SingleChildScrollView(child: fields))
              else
                fields,
              const Divider(height: AppSpacing.lg),
              const _ActionBar(),
            ],
          );
        },
      ),
    );
  }
}

class _FormFields extends StatefulWidget {
  const _FormFields({
    super.key,
    required this.initialDraft,
    required this.references,
    required this.validationErrors,
  });

  final DraftSaveInput initialDraft;
  final ReviewReferences references;
  final List<ValidationError> validationErrors;

  @override
  State<_FormFields> createState() => _FormFieldsState();
}

class _FormFieldsState extends State<_FormFields> {
  final Map<String, TextEditingController> _controllers = {};
  final _keywordController = TextEditingController();

  int? _documentTypeId;
  String? _languageKey;
  String? _countryKey;
  String? _trustLevelKey;
  String? _usageRightsKey;
  String? _metadataQualityKey;
  String? _degreeTypeKey;
  String? _legislationTypeKey;
  String? _effectiveStatusKey;
  String? _keywordLanguageKey;

  DocumentClassificationInput? _primary;
  late List<DocumentClassificationInput> _additional;
  late List<KeywordInput> _keywords;

  // Pending additional-classification picker selection.
  int? _addMainCategoryId;
  int? _addSubCategoryId;

  TextEditingController _c(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    final common = draft.common;
    _documentTypeId = common.documentTypeId;
    _languageKey = common.languageKey;
    _c('languageOther').text = common.languageOther ?? '';
    _countryKey = common.countryKey;
    _trustLevelKey = common.trustLevelKey;
    _usageRightsKey = common.usageRightsKey;
    _metadataQualityKey = common.metadataQualityKey;

    _c('title').text = common.title ?? '';
    _c('summary').text = common.summary ?? '';
    _c('sourceDescription').text = common.sourceDescription ?? '';
    _c('reviewNotes').text = common.reviewNotes ?? '';
    _c('publicationYear').text = common.publicationYear?.toString() ?? '';

    _seedDetails(draft.details);

    _primary = draft.primaryClassification;
    _additional = List.of(draft.additionalClassifications);
    _keywords = List.of(draft.keywords);
  }

  void _seedDetails(DocumentTypeDetails? details) {
    switch (details) {
      case BookDetailsData(
        :final author,
        :final publisher,
        :final publicationPlace,
      ):
        _c('book.author').text = author ?? '';
        _c('book.publisher').text = publisher ?? '';
        _c('book.publicationPlace').text = publicationPlace ?? '';
      case ThesisDetailsData(
        :final researcherName,
        :final degreeTypeKey,
        :final universityName,
        :final supervisorName,
      ):
        _c('thesis.researcherName').text = researcherName ?? '';
        _degreeTypeKey = degreeTypeKey;
        _c('thesis.universityName').text = universityName ?? '';
        _c('thesis.supervisorName').text = supervisorName ?? '';
      case ResearchDetailsData(
        :final researcherName,
        :final journalName,
        :final publishingEntity,
        :final volume,
        :final issue,
      ):
        _c('research.researcherName').text = researcherName ?? '';
        _c('research.journalName').text = journalName ?? '';
        _c('research.publishingEntity').text = publishingEntity ?? '';
        _c('research.volume').text = volume ?? '';
        _c('research.issue').text = issue ?? '';
      case LegislationDetailsData(
        :final legislationTypeKey,
        :final legislationTypeOther,
        :final effectiveStatusKey,
        :final issueNumber,
        :final publicationDate,
        :final legislationNumber,
        :final legislationYear,
        :final effectiveDate,
        :final repealDate,
      ):
        _legislationTypeKey = legislationTypeKey;
        _c('legislation.legislationTypeOther').text =
            legislationTypeOther ?? '';
        _effectiveStatusKey = effectiveStatusKey;
        _c('legislation.issueNumber').text = issueNumber ?? '';
        _c('legislation.publicationDate').text = publicationDate ?? '';
        _c('legislation.legislationNumber').text = legislationNumber ?? '';
        _c('legislation.legislationYear').text =
            legislationYear?.toString() ?? '';
        _c('legislation.effectiveDate').text = effectiveDate ?? '';
        _c('legislation.repealDate').text = repealDate ?? '';
      case CourtCaseDetailsData(
        :final courtName,
        :final caseNumber,
        :final judgmentDate,
        :final judgmentResult,
        :final legalPrinciple,
      ):
        _c('court.courtName').text = courtName ?? '';
        _c('court.caseNumber').text = caseNumber ?? '';
        _c('court.judgmentDate').text = judgmentDate ?? '';
        _c('court.judgmentResult').text = judgmentResult ?? '';
        _c('court.legalPrinciple').text = legalPrinciple ?? '';
      case ReportDetailsData(:final publishingEntity):
        _c('report.publishingEntity').text = publishingEntity ?? '';
      case null:
        break;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _keywordController.dispose();
    super.dispose();
  }

  String? _textOrNull(String key) {
    final value = _controllers[key]?.text.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  void _emit() {
    final draft = DraftSaveInput(
      documentId: widget.initialDraft.documentId,
      common: DocumentCommonMetadata(
        documentTypeId: _documentTypeId,
        title: _textOrNull('title'),
        languageKey: _languageKey,
        languageOther: _languageKey == 'other'
            ? _textOrNull('languageOther')
            : null,
        countryKey: _countryKey,
        publicationYear: int.tryParse(_c('publicationYear').text.trim()),
        summary: _textOrNull('summary'),
        sourceDescription: _textOrNull('sourceDescription'),
        trustLevelKey: _trustLevelKey,
        usageRightsKey: _usageRightsKey,
        metadataQualityKey: _metadataQualityKey,
        reviewNotes: _textOrNull('reviewNotes'),
      ),
      details: _buildDetails(),
      primaryClassification: _primary,
      // Copy the lists so each emitted draft is an independent snapshot; this
      // lets the BLoC detect additions/removals (and keeps dirty tracking
      // correct) instead of aliasing the previous draft's list.
      additionalClassifications: List.of(_additional),
      keywords: List.of(_keywords),
    );
    context.read<ReviewBloc>().add(ReviewDraftEdited(draft));
  }

  DocumentTypeDetails? _buildDetails() {
    final typeKey = widget.references.typeKeyFor(_documentTypeId);
    switch (typeKey) {
      case 'book':
        return BookDetailsData(
          author: _textOrNull('book.author'),
          publisher: _textOrNull('book.publisher'),
          publicationPlace: _textOrNull('book.publicationPlace'),
        );
      case 'thesis':
        return ThesisDetailsData(
          researcherName: _textOrNull('thesis.researcherName'),
          degreeTypeKey: _degreeTypeKey,
          universityName: _textOrNull('thesis.universityName'),
          supervisorName: _textOrNull('thesis.supervisorName'),
        );
      case 'research_paper':
        return ResearchDetailsData(
          researcherName: _textOrNull('research.researcherName'),
          journalName: _textOrNull('research.journalName'),
          publishingEntity: _textOrNull('research.publishingEntity'),
          volume: _textOrNull('research.volume'),
          issue: _textOrNull('research.issue'),
        );
      case 'legislation':
        return LegislationDetailsData(
          legislationTypeKey: _legislationTypeKey,
          legislationTypeOther: _textOrNull('legislation.legislationTypeOther'),
          effectiveStatusKey: _effectiveStatusKey,
          issueNumber: _textOrNull('legislation.issueNumber'),
          publicationDate: _textOrNull('legislation.publicationDate'),
          legislationNumber: _textOrNull('legislation.legislationNumber'),
          legislationYear: int.tryParse(
            _c('legislation.legislationYear').text.trim(),
          ),
          effectiveDate: _textOrNull('legislation.effectiveDate'),
          repealDate: _textOrNull('legislation.repealDate'),
        );
      case 'court_precedent':
        return CourtCaseDetailsData(
          courtName: _textOrNull('court.courtName'),
          caseNumber: _textOrNull('court.caseNumber'),
          judgmentDate: _textOrNull('court.judgmentDate'),
          judgmentResult: _textOrNull('court.judgmentResult'),
          legalPrinciple: _textOrNull('court.legalPrinciple'),
        );
      case 'institutional_report':
        return ReportDetailsData(
          publishingEntity: _textOrNull('report.publishingEntity'),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final references = widget.references;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.validationErrors.isNotEmpty)
          _ValidationSummary(errors: widget.validationErrors),
        _FormSection(
          title: 'البيانات العامة',
          children: [
            _Dropdown<int>(
              label: 'نوع المستند',
              value: _documentTypeId,
              items: [
                for (final t in references.documentTypes)
                  _Option(t.id, t.nameAr),
              ],
              onChanged: (value) {
                setState(() => _documentTypeId = value);
                _emit();
              },
            ),
            _LabeledField(
              label: 'العنوان',
              controller: _c('title'),
              onChanged: _emit,
            ),
            _LabeledField(
              label: 'سنة النشر',
              controller: _c('publicationYear'),
              keyboardType: TextInputType.number,
              onChanged: _emit,
            ),
            _Dropdown<String>(
              label: 'اللغة',
              value: _languageKey,
              items: [
                for (final l in references.languages) _Option(l.key, l.nameAr),
              ],
              onChanged: (value) {
                setState(() {
                  _languageKey = value;
                  if (value != 'other') _c('languageOther').clear();
                });
                _emit();
              },
            ),
            if (_languageKey == 'other')
              _LabeledField(
                label: 'تفاصيل اللغة (اختياري)',
                controller: _c('languageOther'),
                onChanged: _emit,
              ),
            _Dropdown<String>(
              label: 'الدولة',
              value: _countryKey,
              items: [
                for (final c in references.countries) _Option(c.key, c.nameAr),
              ],
              onChanged: (value) {
                setState(() => _countryKey = value);
                _emit();
              },
            ),
            _Dropdown<String>(
              label: 'مستوى الثقة',
              value: _trustLevelKey,
              items: [
                for (final t in references.trustLevels)
                  _Option(t.key, t.nameAr),
              ],
              onChanged: (value) {
                setState(() => _trustLevelKey = value);
                _emit();
              },
            ),
            _Dropdown<String>(
              label: 'حقوق الاستخدام',
              value: _usageRightsKey,
              items: [
                for (final u in references.usageRights)
                  _Option(u.key, u.nameAr),
              ],
              onChanged: (value) {
                setState(() => _usageRightsKey = value);
                _emit();
              },
            ),
            _Dropdown<String>(
              label: 'جودة البيانات الوصفية',
              value: _metadataQualityKey,
              items: [
                for (final m in references.metadataQualities)
                  _Option(m.key, m.nameAr),
              ],
              onChanged: (value) {
                setState(() => _metadataQualityKey = value);
                _emit();
              },
            ),
            _LabeledField(
              label: 'الملخص',
              controller: _c('summary'),
              maxLines: 3,
              onChanged: _emit,
            ),
            _LabeledField(
              label: 'وصف المصدر',
              controller: _c('sourceDescription'),
              maxLines: 2,
              onChanged: _emit,
            ),
            _LabeledField(
              label: 'ملاحظات المراجعة',
              controller: _c('reviewNotes'),
              maxLines: 2,
              onChanged: _emit,
            ),
          ],
        ),
        _typeSpecificSection(),
        if (widget.references.typeKeyFor(_documentTypeId) == 'legislation' &&
            widget.initialDraft.documentId > 0)
          LegislationRelationsSection(
            documentId: widget.initialDraft.documentId,
            legislationDocumentTypeId:
                widget.references.legislationDocumentTypeId,
          ),
        _classificationSection(context),
        _keywordSection(context),
      ],
    );
  }

  Widget _typeSpecificSection() {
    final typeKey = widget.references.typeKeyFor(_documentTypeId);
    final fields = <Widget>[];
    switch (typeKey) {
      case 'book':
        fields.addAll([
          _LabeledField(
            label: 'المؤلف',
            controller: _c('book.author'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'الناشر',
            controller: _c('book.publisher'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'مكان النشر',
            controller: _c('book.publicationPlace'),
            onChanged: _emit,
          ),
        ]);
      case 'thesis':
        fields.addAll([
          _LabeledField(
            label: 'اسم الباحث',
            controller: _c('thesis.researcherName'),
            onChanged: _emit,
          ),
          _Dropdown<String>(
            label: 'نوع الدرجة العلمية',
            value: _degreeTypeKey,
            items: [
              for (final e in kDegreeTypeLabels.entries)
                _Option(e.key, e.value),
            ],
            onChanged: (value) {
              setState(() => _degreeTypeKey = value);
              _emit();
            },
          ),
          _LabeledField(
            label: 'الجامعة',
            controller: _c('thesis.universityName'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'المشرف',
            controller: _c('thesis.supervisorName'),
            onChanged: _emit,
          ),
        ]);
      case 'research_paper':
        fields.addAll([
          _LabeledField(
            label: 'اسم الباحث',
            controller: _c('research.researcherName'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'اسم المجلة',
            controller: _c('research.journalName'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'جهة النشر',
            controller: _c('research.publishingEntity'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'المجلد',
            controller: _c('research.volume'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'العدد',
            controller: _c('research.issue'),
            onChanged: _emit,
          ),
        ]);
      case 'legislation':
        fields.addAll([
          _Dropdown<String>(
            label: 'نوع التشريع',
            value: _legislationTypeKey,
            items: [
              for (final e in kLegislationTypeLabels.entries)
                _Option(e.key, e.value),
            ],
            onChanged: (value) {
              setState(() {
                _legislationTypeKey = value;
                if (value != 'other') {
                  _c('legislation.legislationTypeOther').clear();
                }
              });
              _emit();
            },
          ),
          if (_legislationTypeKey == 'other')
            _LabeledField(
              label: 'نوع التشريع الآخر',
              controller: _c('legislation.legislationTypeOther'),
              onChanged: _emit,
            ),
          _Dropdown<String>(
            label: 'حالة النفاذ',
            value: _effectiveStatusKey,
            items: [
              for (final e in kEffectiveStatusLabels.entries)
                _Option(e.key, e.value),
            ],
            onChanged: (value) {
              setState(() => _effectiveStatusKey = value);
              _emit();
            },
          ),
          _LabeledField(
            label: 'رقم العدد',
            controller: _c('legislation.issueNumber'),
            onChanged: _emit,
          ),
          _DateField(
            label: 'تاريخ النشر',
            controller: _c('legislation.publicationDate'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'رقم التشريع',
            controller: _c('legislation.legislationNumber'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'سنة التشريع',
            controller: _c('legislation.legislationYear'),
            keyboardType: TextInputType.number,
            onChanged: _emit,
          ),
          _DateField(
            label: 'تاريخ النفاذ',
            controller: _c('legislation.effectiveDate'),
            onChanged: _emit,
          ),
          _DateField(
            label: 'تاريخ الإلغاء',
            controller: _c('legislation.repealDate'),
            onChanged: _emit,
          ),
        ]);
      case 'court_precedent':
        fields.addAll([
          _LabeledField(
            label: 'اسم المحكمة',
            controller: _c('court.courtName'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'رقم القضية',
            controller: _c('court.caseNumber'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'تاريخ الحكم (YYYY-MM-DD)',
            controller: _c('court.judgmentDate'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'نتيجة الحكم',
            controller: _c('court.judgmentResult'),
            onChanged: _emit,
          ),
          _LabeledField(
            label: 'المبدأ القانوني',
            controller: _c('court.legalPrinciple'),
            maxLines: 2,
            onChanged: _emit,
          ),
        ]);
      case 'institutional_report':
        fields.add(
          _LabeledField(
            label: 'جهة النشر',
            controller: _c('report.publishingEntity'),
            onChanged: _emit,
          ),
        );
      case 'other':
        fields.add(
          Text(
            'استخدم حقل «ملاحظات المراجعة» لتوضيح نوع المستند.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      default:
        fields.add(
          Text(
            'اختر نوع المستند لعرض الحقول الخاصة به.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
    }
    return _FormSection(title: 'حقول النوع', children: fields);
  }

  Widget _classificationSection(BuildContext context) {
    final references = widget.references;
    final primarySubs = references.subCategoriesFor(_primary?.mainCategoryId);
    final addSubs = references.subCategoriesFor(_addMainCategoryId);
    return _FormSection(
      title: 'التصنيفات',
      children: [
        Text('التصنيف الرئيسي', style: Theme.of(context).textTheme.labelLarge),
        _Dropdown<int>(
          label: 'الفئة الرئيسية',
          value: _primary?.mainCategoryId,
          items: [
            for (final m in references.mainCategories) _Option(m.id, m.nameAr),
          ],
          onChanged: (value) {
            setState(() {
              _primary = value == null
                  ? null
                  : DocumentClassificationInput(mainCategoryId: value);
            });
            _emit();
          },
        ),
        _Dropdown<int>(
          key: ValueKey('primarySub_${_primary?.mainCategoryId}'),
          label: 'الفئة الفرعية',
          value: _primary?.subCategoryId,
          enabled: _primary != null && primarySubs.isNotEmpty,
          items: [for (final s in primarySubs) _Option(s.id, s.nameAr)],
          onChanged: (value) {
            final main = _primary?.mainCategoryId;
            if (main == null) return;
            setState(() {
              _primary = DocumentClassificationInput(
                mainCategoryId: main,
                subCategoryId: value,
              );
            });
            _emit();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text('تصنيفات إضافية', style: Theme.of(context).textTheme.labelLarge),
        ..._additional.asMap().entries.map(
          (entry) => _AdditionalRow(
            label: _classificationLabel(entry.value),
            onRemove: () {
              setState(() => _additional.removeAt(entry.key));
              _emit();
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Dropdown<int>(
          key: const Key('review_add_main'),
          label: 'فئة رئيسية للإضافة',
          value: _addMainCategoryId,
          items: [
            for (final m in references.mainCategories) _Option(m.id, m.nameAr),
          ],
          onChanged: (value) => setState(() {
            _addMainCategoryId = value;
            _addSubCategoryId = null;
          }),
        ),
        _Dropdown<int>(
          key: ValueKey('addSub_$_addMainCategoryId'),
          label: 'فئة فرعية للإضافة',
          value: _addSubCategoryId,
          enabled: _addMainCategoryId != null && addSubs.isNotEmpty,
          items: [for (final s in addSubs) _Option(s.id, s.nameAr)],
          onChanged: (value) => setState(() => _addSubCategoryId = value),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppSecondaryButton(
            label: 'إضافة تصنيف',
            icon: Icons.add,
            onPressed: _addMainCategoryId == null
                ? null
                : () => _addClassification(context),
          ),
        ),
      ],
    );
  }

  void _addClassification(BuildContext context) {
    final main = _addMainCategoryId;
    if (main == null) return;
    final candidate = DocumentClassificationInput(
      mainCategoryId: main,
      subCategoryId: _addSubCategoryId,
    );
    final exists =
        candidate == _primary ||
        _additional.any(
          (c) =>
              c.mainCategoryId == candidate.mainCategoryId &&
              c.subCategoryId == candidate.subCategoryId,
        );
    if (exists) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('هذا التصنيف مُضاف بالفعل.')),
        );
      return;
    }
    setState(() {
      _additional.add(candidate);
      _addMainCategoryId = null;
      _addSubCategoryId = null;
    });
    _emit();
  }

  String _classificationLabel(DocumentClassificationInput c) {
    final main = widget.references.mainCategoryName(c.mainCategoryId);
    if (c.subCategoryId == null) return main;
    return '$main / ${widget.references.subCategoryName(c.subCategoryId!)}';
  }

  Widget _keywordSection(BuildContext context) {
    return _FormSection(
      title: 'الكلمات المفتاحية',
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final entry in _keywords.asMap().entries)
              Chip(
                label: Text(entry.value.displayValue),
                onDeleted: () {
                  setState(() => _keywords.removeAt(entry.key));
                  _emit();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _keywordController,
                decoration: const InputDecoration(
                  labelText: 'أضف كلمة مفتاحية',
                ),
                onSubmitted: (_) => _addKeyword(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: _Dropdown<String>(
                label: 'اللغة',
                value: _keywordLanguageKey,
                items: [
                  for (final l in widget.references.languages)
                    _Option(l.key, l.nameAr),
                ],
                onChanged: (value) =>
                    setState(() => _keywordLanguageKey = value),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              tooltip: 'إضافة الكلمة المفتاحية',
              onPressed: _addKeyword,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  void _addKeyword() {
    final value = _keywordController.text.trim();
    if (value.isEmpty) return;
    final exists = _keywords.any(
      (k) => k.displayValue.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      _keywordController.clear();
      return;
    }
    setState(() {
      _keywords.add(
        KeywordInput(displayValue: value, languageKey: _keywordLanguageKey),
      );
      _keywordController.clear();
    });
    _emit();
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewBloc, ReviewState>(
      buildWhen: (p, c) =>
          p.documentStatus != c.documentStatus ||
          p.operation != c.operation ||
          p.isDirty != c.isDirty ||
          p.aggregate?.workflowStatusKey != c.aggregate?.workflowStatusKey,
      builder: (context, state) {
        final bloc = context.read<ReviewBloc>();
        final loaded = state.documentStatus == ReviewDocumentStatus.loaded;
        final busy = state.isBusy;
        final dirty = state.isDirty;
        final workflowStatus = state.aggregate?.workflowStatusKey;
        final isClassified = workflowStatus == 'classified';
        final isCopied = workflowStatus == 'copied_to_library';
        final isReadyForExport = workflowStatus == 'ready_for_export';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: LinearProgressIndicator(),
              ),
            if (loaded && dirty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'لديك تعديلات غير محفوظة. احفظ المسودة أولًا لاعتماد التصنيف.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppStatusColors.warning.foreground,
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppPrimaryButton(
                  label: 'حفظ كمسودة',
                  icon: Icons.save_outlined,
                  onPressed: loaded && !busy
                      ? () => bloc.add(const ReviewDraftSaved())
                      : null,
                ),
                if (!isClassified && !isCopied && !isReadyForExport)
                  AppSecondaryButton(
                    label: 'اعتماد التصنيف',
                    icon: Icons.verified_outlined,
                    onPressed: loaded && !busy && !dirty
                        ? () => bloc.add(const ReviewClassificationApproved())
                        : null,
                  ),
                if (isClassified)
                  AppSecondaryButton(
                    label: 'إعادة إلى قيد التصنيف',
                    icon: Icons.undo,
                    onPressed: !busy
                        ? () => _confirmReturn(context, bloc)
                        : null,
                  ),
                if (!isCopied && !isReadyForExport)
                  BlocBuilder<ManagedCopyBloc, ManagedCopyState>(
                    builder: (context, copyState) => AppSecondaryButton(
                      label: copyState.isRunning
                          ? 'جارٍ النسخ والتحقق...'
                          : 'نسخ إلى المكتبة المدارة',
                      icon: Icons.content_copy_outlined,
                      onPressed:
                          loaded &&
                              isClassified &&
                              !busy &&
                              !dirty &&
                              !copyState.isRunning
                          ? () =>
                                _confirmCopy(context, state.selectedDocumentId!)
                          : null,
                    ),
                  ),
                if (isCopied)
                  BlocBuilder<MarkReadyForExportBloc, MarkReadyForExportState>(
                    builder: (context, exportState) => AppSecondaryButton(
                      label: exportState.isRunning
                          ? 'جارٍ التعيين...'
                          : 'تعيين جاهز للتصدير',
                      icon: Icons.outbox_outlined,
                      onPressed:
                          loaded && !busy && !dirty && !exportState.isRunning
                          ? () => context.read<MarkReadyForExportBloc>().add(
                              MarkReadyForExportRequested(
                                state.selectedDocumentId!,
                              ),
                            )
                          : null,
                    ),
                  ),
                if (isReadyForExport)
                  const StatusChip(
                    label: 'جاهز للتصدير ✓',
                    status: AppStatusColors.teal,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmReturn(BuildContext context, ReviewBloc bloc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة إلى قيد التصنيف'),
        content: const Text(
          'سيُعاد المستند إلى حالة «قيد التصنيف» ويُلغى اعتماده الحالي. '
          'لن يتأثر أي ملف أصلي. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      bloc.add(const ReviewReturnedToInProgress());
    }
  }

  Future<void> _confirmCopy(BuildContext context, int documentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('نسخ إلى المكتبة المدارة'),
        content: const Text(
          'سيُنشئ مرجعي نسخة PDF مدارة بعد إنشاء نسخة احتياطية والتحقق من التطابق. لن يتغير الملف الأصلي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('بدء النسخ'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<ManagedCopyBloc>().add(ManagedCopyRequested(documentId));
    }
  }
}

// --------------------------------------------------------------------------
// Small shared form widgets
// --------------------------------------------------------------------------

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => onChanged(),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYY-MM-DD',
        suffixIcon: IconButton(
          tooltip: 'اختيار التاريخ',
          onPressed: () => _pick(context),
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ),
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final parsed = DateTime.tryParse(controller.text);
    final selected = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime(2100),
      helpText: label,
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (selected == null) return;
    controller.text =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
    onChanged();
  }
}

class _Option<T> {
  const _Option(this.value, this.label);
  final T value;
  final String label;
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<_Option<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Guard against a stored value that is not among the active options (e.g. a
    // reference that became inactive): show "غير محدد" instead of asserting.
    final bool valuePresent = items.any((item) => item.value == value);
    return DropdownButtonFormField<T>(
      initialValue: valuePresent ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      onChanged: enabled ? onChanged : null,
      items: [
        const DropdownMenuItem(value: null, child: Text('— غير محدد —')),
        ...items.map(
          (item) => DropdownMenuItem<T>(
            value: item.value,
            child: Text(item.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _AdditionalRow extends StatelessWidget {
  const _AdditionalRow({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: 'إزالة التصنيف',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({required this.errors});

  final List<ValidationError> errors;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppStatusColors.danger.background,
        borderRadius: AppRadii.control,
        border: Border.all(
          color: AppStatusColors.danger.foreground.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: AppStatusColors.danger.foreground,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'تعذّر اعتماد التصنيف. عالج الملاحظات التالية:',
                  style: text.labelLarge?.copyWith(
                    color: AppStatusColors.danger.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final error in errors)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${reviewErrorMessage(error)}',
                style: text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

String _queueTitle(ReviewQueueItem item) {
  if (item.title?.trim().isNotEmpty == true) return item.title!.trim();
  if (item.sourceFileName?.trim().isNotEmpty == true) {
    return item.sourceFileName!.trim();
  }
  return item.documentCode ?? 'مستند بلا عنوان';
}

StatusColor _workflowColor(String key) => switch (key) {
  'classified' || 'copied_to_library' => AppStatusColors.success,
  'needs_review' => AppStatusColors.warning,
  'in_progress' => AppStatusColors.info,
  'ready_for_export' => AppStatusColors.teal,
  _ => AppStatusColors.neutral,
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
