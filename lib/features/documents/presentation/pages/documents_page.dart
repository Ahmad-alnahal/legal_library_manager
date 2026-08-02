import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/country_flag_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../file_open/domain/entities/file_health_eligibility.dart';
import '../../../file_open/presentation/bloc/file_open_bloc.dart';
import '../../../file_open/presentation/widgets/file_open_feedback.dart';
import '../../../file_open/presentation/widgets/open_actions.dart';
import '../../../reference/domain/entities/document_type_ref.dart';
import '../../../reference/domain/entities/main_category_ref.dart';
import '../../../reference/domain/entities/reference_item.dart';
import '../../../reference/domain/entities/sub_category_ref.dart';
import '../../../reference/domain/repositories/reference_repository.dart';
import '../../domain/entities/document_list_item.dart';
import '../../domain/entities/document_list_query.dart';
import '../../domain/repositories/document_list_repository.dart';
import '../bloc/document_list_bloc.dart';
import '../bloc/document_list_event.dart';
import '../bloc/document_list_state.dart';

class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              getIt<DocumentListBloc>()..add(const DocumentListStarted()),
        ),
        BlocProvider(create: (_) => getIt<FileOpenBloc>()),
      ],
      child: FileOpenFeedbackListener(
        child: _DocumentsWorkspace(
          references: getIt<ReferenceRepository>(),
          documents: getIt<DocumentListRepository>(),
        ),
      ),
    );
  }
}

class _DocumentsWorkspace extends StatefulWidget {
  const _DocumentsWorkspace({
    required this.references,
    required this.documents,
  });

  final ReferenceRepository references;
  final DocumentListRepository documents;

  @override
  State<_DocumentsWorkspace> createState() => _DocumentsWorkspaceState();
}

class _DocumentsWorkspaceState extends State<_DocumentsWorkspace> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  late final Future<_FilterReferences> _referenceData;
  bool _filtersVisible = false;

  @override
  void initState() {
    super.initState();
    _referenceData = _FilterReferences.load(widget.references);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 240) {
      context.read<DocumentListBloc>().add(
        const DocumentListNextPageRequested(),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentListBloc, DocumentListState>(
      builder: (context, state) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            return CustomScrollView(
              controller: _scrollController,
              key: const Key('documents_scroll_view'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(AppSpacing.pagePadding),
                  sliver: SliverList.list(
                    children: [
                      const PageHeader(
                        title: 'المستندات المؤرشفة',
                        subtitle:
                            'ابحث وصفّ المستندات القانونية وراجع ملفاتها المصدرية بأمان.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Toolbar(
                        state: state,
                        compact: compact,
                        searchController: _searchController,
                        searchFocus: _searchFocus,
                        filtersVisible: _filtersVisible,
                        onToggleFilters: () =>
                            setState(() => _filtersVisible = !_filtersVisible),
                      ),
                      if (_filtersVisible) ...[
                        const SizedBox(height: AppSpacing.md),
                        FutureBuilder<_FilterReferences>(
                          future: _referenceData,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const _ReferenceLoadFailure();
                            }
                            if (!snapshot.hasData) {
                              return const AppPanel(
                                child: LinearProgressIndicator(),
                              );
                            }
                            return _FilterPanel(
                              data: snapshot.requireData,
                              filters: state.filters,
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _ResultsSummary(state: state),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
                ..._resultSlivers(state),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: AppSpacing.pagePadding),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _resultSlivers(DocumentListState state) {
    if (state.status == DocumentListStatus.initial ||
        state.status == DocumentListStatus.loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (state.status == DocumentListStatus.failure) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: _LoadFailure()),
      ];
    }
    if (state.items.isEmpty) {
      final filtered = _activeFilterCount(state.filters) > 0;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: filtered ? Icons.search_off : Icons.description_outlined,
            title: filtered ? 'لا توجد نتائج مطابقة' : 'لا توجد مستندات بعد',
            message: filtered
                ? 'جرّب تعديل عبارة البحث أو إزالة بعض عوامل التصفية.'
                : 'ستظهر المستندات هنا بعد استيرادها وفهرستها.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
        sliver: SliverList.separated(
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => _DocumentRow(
            item: state.items[index],
            documents: widget.documents,
          ),
        ),
      ),
      if (state.isLoadingMore)
        const SliverPadding(
          padding: EdgeInsets.all(AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (state.hasMore)
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: AppSecondaryButton(
                label: 'تحميل المزيد',
                icon: Icons.expand_more,
                onPressed: () => context.read<DocumentListBloc>().add(
                  const DocumentListNextPageRequested(),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.compact,
    required this.searchController,
    required this.searchFocus,
    required this.filtersVisible,
    required this.onToggleFilters,
  });

  final DocumentListState state;
  final bool compact;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final bool filtersVisible;
  final VoidCallback onToggleFilters;

  @override
  Widget build(BuildContext context) {
    final search = AppTextField(
      controller: searchController,
      focusNode: searchFocus,
      hintText: 'ابحث بالعنوان أو الرمز أو الكلمات المفتاحية...',
      prefixIcon: Icons.search,
      onChanged: (value) => context.read<DocumentListBloc>().add(
        DocumentListSearchChanged(value),
      ),
      suffixIcon: searchController.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'مسح البحث',
              icon: const Icon(Icons.close),
              onPressed: () {
                searchController.clear();
                context.read<DocumentListBloc>().add(
                  const DocumentListSearchChanged(''),
                );
                searchFocus.requestFocus();
              },
            ),
    );
    final controls = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FilterToggle(
          count: _activeFilterCount(state.filters),
          expanded: filtersVisible,
          onPressed: onToggleFilters,
        ),
        _SortMenu(value: state.sort),
        IconButton(
          tooltip: 'تحديث القائمة',
          onPressed: () => context.read<DocumentListBloc>().add(
            const DocumentListRefreshed(),
          ),
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
    return AppPanel(
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: AppSpacing.sm),
                controls,
              ],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: AppSpacing.sm),
                controls,
              ],
            ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({
    required this.count,
    required this.expanded,
    required this.onPressed,
  });

  final int count;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: AppSecondaryButton(
        label: expanded ? 'إخفاء التصفية' : 'التصفية',
        icon: Icons.filter_list,
        onPressed: onPressed,
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value});

  final DocumentListSort value;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DocumentListSort>(
      tooltip: 'ترتيب النتائج',
      initialValue: value,
      onSelected: (sort) =>
          context.read<DocumentListBloc>().add(DocumentListSortChanged(sort)),
      itemBuilder: (_) => DocumentListSort.values
          .map(
            (sort) => PopupMenuItem(value: sort, child: Text(_sortLabel(sort))),
          )
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.sort, size: 18),
        label: Text(_sortLabel(value)),
        backgroundColor: AppColors.surfaceMuted,
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({required this.data, required this.filters});

  final _FilterReferences data;
  final DocumentListFilters filters;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  void _apply(DocumentListFilters filters) {
    context.read<DocumentListBloc>().add(DocumentListFiltersChanged(filters));
  }

  @override
  Widget build(BuildContext context) {
    final filters = widget.filters;
    final subcategories = widget.data.subcategories
        .where((item) => item.mainCategoryId == filters.mainCategoryId)
        .toList();
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'عوامل التصفية',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _activeFilterCount(filters) == 0
                    ? null
                    : () => _apply(DocumentListFilters(search: filters.search)),
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('مسح الكل'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 1000
                  ? (constraints.maxWidth - AppSpacing.md * 3) / 4
                  : constraints.maxWidth >= 620
                  ? (constraints.maxWidth - AppSpacing.md) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _FilterDropdown<String>(
                    width: width,
                    label: 'حالة سير العمل',
                    value: filters.workflowStatusKey,
                    items: widget.data.workflowStatuses
                        .map((e) => _Choice(e.key, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        workflowStatusKey: value,
                        clearWorkflowStatus: value == null,
                      ),
                    ),
                  ),
                  _FilterDropdown<int>(
                    width: width,
                    label: 'نوع المستند',
                    value: filters.documentTypeId,
                    items: widget.data.documentTypes
                        .map((e) => _Choice(e.id, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        documentTypeId: value,
                        clearDocumentType: value == null,
                      ),
                    ),
                  ),
                  _FilterDropdown<int>(
                    width: width,
                    label: 'الفئة الرئيسية',
                    value: filters.mainCategoryId,
                    items: widget.data.mainCategories
                        .map((e) => _Choice(e.id, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        mainCategoryId: value,
                        clearMainCategory: value == null,
                        clearSubCategory: true,
                      ),
                    ),
                  ),
                  _FilterDropdown<int>(
                    width: width,
                    label: 'الفئة الفرعية',
                    value: filters.subCategoryId,
                    enabled: filters.mainCategoryId != null,
                    items: subcategories
                        .map((e) => _Choice(e.id, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        subCategoryId: value,
                        clearSubCategory: value == null,
                      ),
                    ),
                  ),
                  _FilterDropdown<String>(
                    width: width,
                    label: 'الدولة',
                    value: filters.countryKey,
                    items: widget.data.countries
                        .map((e) => _Choice(e.key, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        countryKey: value,
                        clearCountry: value == null,
                      ),
                    ),
                  ),
                  _FilterDropdown<String>(
                    width: width,
                    label: 'اللغة',
                    value: filters.languageKey,
                    items: widget.data.languages
                        .map((e) => _Choice(e.key, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        languageKey: value,
                        clearLanguage: value == null,
                      ),
                    ),
                  ),
                  _FilterDropdown<String>(
                    width: width,
                    label: 'مستوى الثقة',
                    value: filters.trustLevelKey,
                    items: widget.data.trustLevels
                        .map((e) => _Choice(e.key, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        trustLevelKey: value,
                        clearTrustLevel: value == null,
                      ),
                    ),
                  ),
                  _FilterDropdown<String>(
                    width: width,
                    label: 'سلامة الملف',
                    value: filters.fileHealthKey,
                    items: widget.data.fileHealthStatuses
                        .map((e) => _Choice(e.key, e.nameAr))
                        .toList(),
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        fileHealthKey: value,
                        clearFileHealth: value == null,
                      ),
                    ),
                  ),
                  _FilterDropdown<DuplicateFilter>(
                    width: width,
                    label: 'التكرارات',
                    value: filters.duplicateFilter,
                    includeAll: false,
                    items: const [
                      _Choice(DuplicateFilter.any, 'الكل'),
                      _Choice(DuplicateFilter.duplicatesOnly, 'مكررة فقط'),
                      _Choice(DuplicateFilter.withoutDuplicates, 'دون تكرارات'),
                    ],
                    onChanged: (value) => _apply(
                      filters.copyWith(
                        duplicateFilter: value ?? DuplicateFilter.any,
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
}

class _Choice<T> {
  const _Choice(this.value, this.label);
  final T value;
  final String label;
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.includeAll = true,
  });

  final double width;
  final String label;
  final T? value;
  final List<_Choice<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final bool includeAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        onChanged: enabled ? onChanged : null,
        items: [
          if (includeAll)
            DropdownMenuItem<T>(value: null, child: const Text('الكل')),
          ...items.map(
            (item) => DropdownMenuItem<T>(
              value: item.value,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({required this.state});
  final DocumentListState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'النتائج: ${state.totalCount} | المعروض: ${state.items.length}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (state.errorMessage == 'document_list_next_page_failed')
          TextButton.icon(
            onPressed: () => context.read<DocumentListBloc>().add(
              const DocumentListNextPageRequested(),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('إعادة محاولة تحميل المزيد'),
          ),
      ],
    );
  }
}

class _DocumentRow extends StatefulWidget {
  const _DocumentRow({required this.item, required this.documents});

  final DocumentListItem item;
  final DocumentListRepository documents;

  @override
  State<_DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends State<_DocumentRow> {
  Future<List<DocumentSourceFileItem>>? _sourceFiles;

  void _onExpanded(bool expanded) {
    if (expanded && _sourceFiles == null) {
      setState(() {
        _sourceFiles = widget.documents.getSourceFiles(widget.item.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final title = item.title?.trim().isNotEmpty == true
        ? item.title!
        : item.sourceFileName?.trim().isNotEmpty == true
        ? item.sourceFileName!
        : item.documentCode ?? 'مستند بلا عنوان';
    final category = [
      item.primaryMainCategoryNameAr,
      item.primarySubCategoryNameAr,
    ].whereType<String>().join(' / ');
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('document_row_${item.id}'),
        onExpansionChanged: _onExpanded,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.documentCode != null) Text(item.documentCode!),
              if (item.documentTypeNameAr != null)
                Text(item.documentTypeNameAr!),
              if (category.isNotEmpty) Text(category),
              if (item.publicationYear != null) Text('${item.publicationYear}'),
              if (item.countryKey != null)
                CountryFlagView(countryCode: item.countryKey!),
              StatusChip(
                label: _workflowLabel(item.workflowStatusKey),
                status: _workflowColor(item.workflowStatusKey),
              ),
              if (item.hasDuplicate)
                const _Indicator(
                  icon: Icons.content_copy,
                  label: 'مكرر',
                  color: AppStatusColors.duplicate,
                ),
              if (item.hasCorruptedFile)
                const _Indicator(
                  icon: Icons.broken_image_outlined,
                  label: 'تالف',
                  color: AppStatusColors.danger,
                ),
              if (item.hasUnreadableFile)
                const _Indicator(
                  icon: Icons.visibility_off_outlined,
                  label: 'غير قابل للقراءة',
                  color: AppStatusColors.warning,
                ),
              Text('${item.fileCount} ملف'),
            ],
          ),
        ),
        children: [
          const Divider(),
          _SourceFiles(future: _sourceFiles),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final StatusColor color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Icon(icon, size: 18, color: color.foreground),
    );
  }
}

class _SourceFiles extends StatelessWidget {
  const _SourceFiles({required this.future});
  final Future<List<DocumentSourceFileItem>>? future;

  @override
  Widget build(BuildContext context) {
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<DocumentSourceFileItem>>(
      future: future,
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
        if (snapshot.requireData.isEmpty) {
          return const Text('لا توجد ملفات مصدرية مسجلة لهذا المستند.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الملفات المصدرية - للقراءة فقط',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...snapshot.requireData.map(
              (file) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          file.fileName,
                          textDirection: TextDirection.ltr,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        SelectableText(
                          file.absolutePath,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${_fileRoleLabel(file.fileRoleKey)} | '
                          '${_fileHealthLabel(file.fileHealthKey)} | '
                          '${_formatBytes(file.fileSizeBytes)} | '
                          '${file.isReadOnlySource ? 'مصدر للقراءة فقط' : 'نسخة مُدارة'}',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        OpenActions(
                          fileId: file.id,
                          showOpenFile: canOpenFileDirectly(file.fileHealthKey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const EmptyState(
          icon: Icons.error_outline,
          title: 'تعذّر تحميل المستندات',
          message: 'لم نتمكن من قراءة قائمة المستندات. حاول مرة أخرى.',
        ),
        const SizedBox(height: AppSpacing.md),
        AppSecondaryButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh,
          onPressed: () => context.read<DocumentListBloc>().add(
            const DocumentListRefreshed(),
          ),
        ),
      ],
    );
  }
}

class _ReferenceLoadFailure extends StatelessWidget {
  const _ReferenceLoadFailure();

  @override
  Widget build(BuildContext context) {
    return const AppPanel(
      borderColor: Color(0xFFF3B5B5),
      child: Text('تعذّر تحميل خيارات التصفية المرجعية.'),
    );
  }
}

class _FilterReferences {
  const _FilterReferences({
    required this.documentTypes,
    required this.mainCategories,
    required this.subcategories,
    required this.countries,
    required this.languages,
    required this.trustLevels,
    required this.workflowStatuses,
    required this.fileHealthStatuses,
  });

  final List<DocumentTypeRef> documentTypes;
  final List<MainCategoryRef> mainCategories;
  final List<SubCategoryRef> subcategories;
  final List<ReferenceItem> countries;
  final List<ReferenceItem> languages;
  final List<ReferenceItem> trustLevels;
  final List<ReferenceItem> workflowStatuses;
  final List<ReferenceItem> fileHealthStatuses;

  static Future<_FilterReferences> load(ReferenceRepository repo) async {
    final (
      documentTypes,
      mainCategories,
      subcategories,
      countries,
      languages,
      trustLevels,
      workflowStatuses,
      fileHealthStatuses,
    ) = await (
      repo.getDocumentTypes(),
      repo.getMainCategories(),
      repo.getSubCategories(),
      repo.getCountries(),
      repo.getLanguages(),
      repo.getTrustLevels(),
      repo.getWorkflowStatuses(),
      repo.getFileHealthStatuses(),
    ).wait;
    return _FilterReferences(
      documentTypes: documentTypes,
      mainCategories: mainCategories,
      subcategories: subcategories,
      countries: countries,
      languages: languages,
      trustLevels: trustLevels,
      workflowStatuses: workflowStatuses,
      fileHealthStatuses: fileHealthStatuses,
    );
  }
}

int _activeFilterCount(DocumentListFilters filters) {
  return [
    filters.workflowStatusKey,
    filters.documentTypeId,
    filters.mainCategoryId,
    filters.subCategoryId,
    filters.countryKey,
    filters.languageKey,
    filters.trustLevelKey,
    filters.fileHealthKey,
    if (filters.duplicateFilter != DuplicateFilter.any) filters.duplicateFilter,
  ].where((value) => value != null).length;
}

String _sortLabel(DocumentListSort sort) => switch (sort) {
  DocumentListSort.updatedNewest => 'الأحدث تحديثًا',
  DocumentListSort.updatedOldest => 'الأقدم تحديثًا',
  DocumentListSort.titleAscending => 'العنوان: أ - ي',
  DocumentListSort.titleDescending => 'العنوان: ي - أ',
  DocumentListSort.publicationYearNewest => 'سنة النشر: الأحدث',
  DocumentListSort.publicationYearOldest => 'سنة النشر: الأقدم',
};

String _workflowLabel(String key) => switch (key) {
  WorkflowStatusKey.imported => 'مستورد',
  WorkflowStatusKey.needsReview => 'يحتاج مراجعة',
  WorkflowStatusKey.inProgress => 'قيد التصنيف',
  WorkflowStatusKey.classified => 'مصنف',
  WorkflowStatusKey.copiedToLibrary => 'نُسخ إلى المكتبة',
  WorkflowStatusKey.readyForExport => 'جاهز للتصدير',
  WorkflowStatusKey.archived => 'مؤرشف',
  _ => key,
};

StatusColor _workflowColor(String key) => switch (key) {
  WorkflowStatusKey.classified ||
  WorkflowStatusKey.copiedToLibrary => AppStatusColors.success,
  WorkflowStatusKey.needsReview => AppStatusColors.warning,
  WorkflowStatusKey.inProgress => AppStatusColors.info,
  WorkflowStatusKey.readyForExport => AppStatusColors.teal,
  _ => AppStatusColors.neutral,
};

String _fileRoleLabel(String key) => switch (key) {
  FileRoleKey.sourceOriginal => 'ملف أصلي',
  FileRoleKey.managedCopy => 'نسخة مُدارة',
  FileRoleKey.convertedPdf => 'PDF محوّل',
  FileRoleKey.exportCopy => 'نسخة تصدير',
  _ => key,
};

String _fileHealthLabel(String key) => switch (key) {
  FileHealthKey.healthy => 'سليم',
  FileHealthKey.corrupted => 'تالف',
  FileHealthKey.unreadable => 'غير قابل للقراءة',
  FileHealthKey.missing => 'مفقود',
  _ => 'غير معروف',
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
