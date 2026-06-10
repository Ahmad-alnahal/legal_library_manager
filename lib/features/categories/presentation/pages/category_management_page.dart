import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/validation/category_name.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/managed_main_category.dart';
import '../../domain/entities/managed_sub_category.dart';
import '../../domain/services/category_management_service.dart';
import '../bloc/category_management_bloc.dart';
import '../bloc/category_management_event.dart';
import '../bloc/category_management_state.dart';
import '../widgets/category_labels.dart';

/// Operation keys whose feedback is shown inline inside the form dialog (which
/// stays open and preserves entered values on failure), so the page-level
/// listener must not also surface a validation snackbar for them.
const Set<String> _dialogOperationKeys = {
  'main_added',
  'main_updated',
  'sub_added',
  'sub_updated',
};

/// Reorder operations refresh the list silently; no success snackbar is shown.
const Set<String> _silentOperationKeys = {'main_reordered', 'sub_reordered'};

/// The Category Management workspace: a standalone Arabic-first RTL page for
/// managing main categories and their subcategories. Completely separate from
/// the Document Review workspace. No deletion is offered and no filesystem
/// action is ever performed here. Sort order is managed exclusively through the
/// up/down reorder controls; numeric positions are never surfaced.
class CategoryManagementPage extends StatelessWidget {
  const CategoryManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CategoryManagementBloc>(
      create: (_) =>
          getIt<CategoryManagementBloc>()
            ..add(const CategoryManagementStarted()),
      child: const _CategoryManagementView(),
    );
  }
}

class _CategoryManagementView extends StatefulWidget {
  const _CategoryManagementView();

  @override
  State<_CategoryManagementView> createState() =>
      _CategoryManagementViewState();
}

class _CategoryManagementViewState extends State<_CategoryManagementView> {
  int _lastOpSeq = 0;

  void _onState(BuildContext context, CategoryManagementState state) {
    if (state.opSeq == _lastOpSeq) return;
    _lastOpSeq = state.opSeq;
    switch (state.lastOutcome) {
      case CategoryOpOutcome.success:
        if (_silentOperationKeys.contains(state.lastOperationKey)) break;
        _snack(context, categoryOpSuccessMessage(state.lastOperationKey));
        break;
      case CategoryOpOutcome.validationFailure:
        // Add/edit failures are shown inline in the still-open form dialog.
        if (_dialogOperationKeys.contains(state.lastOperationKey)) break;
        final message = state.validationErrors.isEmpty
            ? categoryUnexpectedErrorMessage
            : categoryErrorMessage(state.validationErrors.first);
        _snack(context, message);
        break;
      case CategoryOpOutcome.error:
        _snack(context, categoryUnexpectedErrorMessage);
        break;
      case CategoryOpOutcome.none:
        break;
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bool compactHeight = MediaQuery.sizeOf(context).height < 420;
    return BlocListener<CategoryManagementBloc, CategoryManagementState>(
      listenWhen: (p, c) => p.opSeq != c.opSeq,
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
                title: 'إدارة التصنيفات',
                subtitle:
                    'أدِر الفئات الرئيسية والفرعية المستخدمة في تصنيف المستندات. '
                    'لا يتم حذف أي تصنيف؛ يمكن تعطيله مع بقاء المستندات القائمة كما هي.',
              ),
            if (!compactHeight) const SizedBox(height: AppSpacing.md),
            const _Toolbar(),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child:
                  BlocBuilder<CategoryManagementBloc, CategoryManagementState>(
                    buildWhen: (p, c) =>
                        p.loadStatus != c.loadStatus ||
                        p.mainCategories != c.mainCategories ||
                        p.subCategories != c.subCategories ||
                        p.selectedMainCategoryId != c.selectedMainCategoryId ||
                        p.showInactive != c.showInactive,
                    builder: (context, state) {
                      switch (state.loadStatus) {
                        case CategoryLoadStatus.initial:
                        case CategoryLoadStatus.loading:
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        case CategoryLoadStatus.failure:
                          return _ErrorRetry(
                            message: 'تعذّر تحميل التصنيفات.',
                            onRetry: () => context
                                .read<CategoryManagementBloc>()
                                .add(const CategoryManagementRetryRequested()),
                          );
                        case CategoryLoadStatus.success:
                          return _Panels(state: state);
                      }
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CategoryManagementBloc, CategoryManagementState>(
      buildWhen: (p, c) =>
          p.showInactive != c.showInactive || p.loadStatus != c.loadStatus,
      builder: (context, state) {
        final bloc = context.read<CategoryManagementBloc>();
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppPrimaryButton(
              key: const Key('category_add_main'),
              label: 'إضافة فئة رئيسية',
              icon: Icons.add,
              onPressed: state.loadStatus == CategoryLoadStatus.success
                  ? () => _addMain(context, bloc)
                  : null,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('إظهار غير المفعّلة')),
                Switch(
                  key: const Key('category_show_inactive'),
                  value: state.showInactive,
                  onChanged: (value) =>
                      bloc.add(CategoryShowInactiveToggled(value)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Panels extends StatelessWidget {
  const _Panels({required this.state});

  final CategoryManagementState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final main = _MainCategoryPanel(state: state);
        final sub = _SubCategoryPanel(state: state);
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: main),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 6, child: sub),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 320, child: main),
              const SizedBox(height: AppSpacing.md),
              SizedBox(height: 360, child: sub),
            ],
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------------------
// Main categories
// --------------------------------------------------------------------------

class _MainCategoryPanel extends StatelessWidget {
  const _MainCategoryPanel({required this.state});

  final CategoryManagementState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<CategoryManagementBloc>();
    final items = state.showInactive
        ? state.mainCategories
        : state.mainCategories.where((m) => m.isActive).toList();
    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الفئات الرئيسية',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('لا توجد فئات رئيسية لعرضها.'))
                : ListView.separated(
                    primary: false,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, index) {
                      final m = items[index];
                      return _MainTile(
                        category: m,
                        selected: m.id == state.selectedMainCategoryId,
                        busy: state.isBusy,
                        onSelect: () => bloc.add(CategoryMainSelected(m.id)),
                        onEdit: () => _editMain(context, bloc, m),
                        onToggleActive: () =>
                            _toggleMainActive(context, bloc, m),
                        onMoveUp: (!state.isBusy && index > 0)
                            ? () => bloc.add(
                                MainCategoryReorderRequested(
                                  idA: m.id,
                                  idB: items[index - 1].id,
                                ),
                              )
                            : null,
                        onMoveDown: (!state.isBusy && index < items.length - 1)
                            ? () => bloc.add(
                                MainCategoryReorderRequested(
                                  idA: m.id,
                                  idB: items[index + 1].id,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MainTile extends StatelessWidget {
  const _MainTile({
    required this.category,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onEdit,
    required this.onToggleActive,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ManagedMainCategory category;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  /// Null when this is the first displayed item (disabled).
  final VoidCallback? onMoveUp;

  /// Null when this is the last displayed item (disabled).
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppColors.navSelected : AppColors.surfaceMuted,
      borderRadius: AppRadii.control,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('category_main_tile_${category.id}'),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadii.control,
            border: Border.all(
              color: selected ? AppColors.navSelectedAccent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.nameAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      category.nameEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: text.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _ActiveChip(isActive: category.isActive),
              IconButton(
                key: Key('category_main_move_up_${category.id}'),
                tooltip: 'تحريك لأعلى',
                visualDensity: VisualDensity.compact,
                onPressed: onMoveUp,
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                key: Key('category_main_move_down_${category.id}'),
                tooltip: 'تحريك لأسفل',
                visualDensity: VisualDensity.compact,
                onPressed: onMoveDown,
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                tooltip: 'تعديل',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              Switch(
                key: Key('category_main_active_${category.id}'),
                value: category.isActive,
                onChanged: busy ? null : (_) => onToggleActive(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Subcategories
// --------------------------------------------------------------------------

class _SubCategoryPanel extends StatelessWidget {
  const _SubCategoryPanel({required this.state});

  final CategoryManagementState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<CategoryManagementBloc>();
    final selectedId = state.selectedMainCategoryId;
    ManagedMainCategory? selectedMain;
    if (selectedId != null) {
      for (final m in state.mainCategories) {
        if (m.id == selectedId) {
          selectedMain = m;
          break;
        }
      }
    }
    final subs = state.subCategoriesForSelected;
    final items = state.showInactive
        ? subs
        : subs.where((s) => s.isActive).toList();

    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                selectedMain == null
                    ? 'الفئات الفرعية'
                    : 'الفئات الفرعية — ${selectedMain.nameAr}',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
              final button = AppSecondaryButton(
                key: const Key('category_add_sub'),
                label: 'إضافة فئة فرعية',
                icon: Icons.add,
                onPressed:
                    (selectedId != null &&
                        selectedMain?.isActive == true &&
                        !state.isBusy)
                    ? () => _addSub(context, bloc, selectedId)
                    : null,
              );
              if (constraints.maxWidth < 430) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: button,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  button,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: selectedId == null
                ? const Center(
                    child: Text('اختر فئة رئيسية لعرض فئاتها الفرعية.'),
                  )
                : items.isEmpty
                ? const Center(child: Text('لا توجد فئات فرعية لعرضها.'))
                : ListView.separated(
                    primary: false,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, index) {
                      final s = items[index];
                      return _SubTile(
                        category: s,
                        busy: state.isBusy,
                        onEdit: () => _editSub(context, bloc, s),
                        onToggleActive: () =>
                            _toggleSubActive(context, bloc, s),
                        onMove: () => _moveSub(context, bloc, state, s),
                        onMoveUp: (!state.isBusy && index > 0)
                            ? () => bloc.add(
                                SubCategoryReorderRequested(
                                  idA: s.id,
                                  idB: items[index - 1].id,
                                ),
                              )
                            : null,
                        onMoveDown: (!state.isBusy && index < items.length - 1)
                            ? () => bloc.add(
                                SubCategoryReorderRequested(
                                  idA: s.id,
                                  idB: items[index + 1].id,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubTile extends StatelessWidget {
  const _SubTile({
    required this.category,
    required this.busy,
    required this.onEdit,
    required this.onToggleActive,
    required this.onMove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ManagedSubCategory category;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onMove;

  /// Null when this is the first displayed sibling (disabled).
  final VoidCallback? onMoveUp;

  /// Null when this is the last displayed sibling (disabled).
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: Key('category_sub_tile_${category.id}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.control,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.nameAr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  category.nameEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: text.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _ActiveChip(isActive: category.isActive),
          IconButton(
            key: Key('category_sub_move_up_${category.id}'),
            tooltip: 'تحريك لأعلى',
            visualDensity: VisualDensity.compact,
            onPressed: onMoveUp,
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          IconButton(
            key: Key('category_sub_move_down_${category.id}'),
            tooltip: 'تحريك لأسفل',
            visualDensity: VisualDensity.compact,
            onPressed: onMoveDown,
            icon: const Icon(Icons.arrow_downward, size: 18),
          ),
          IconButton(
            tooltip: 'تعديل',
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            key: Key('category_sub_move_${category.id}'),
            tooltip: 'نقل إلى فئة رئيسية أخرى',
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : onMove,
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
          ),
          Switch(
            key: Key('category_sub_active_${category.id}'),
            value: category.isActive,
            onChanged: busy ? null : (_) => onToggleActive(),
          ),
        ],
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: isActive ? 'مفعّلة' : 'غير مفعّلة',
      status: isActive ? AppStatusColors.success : AppStatusColors.neutral,
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          AppSecondaryButton(
            label: 'إعادة المحاولة',
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Dialog actions
// --------------------------------------------------------------------------

void _addMain(BuildContext context, CategoryManagementBloc bloc) {
  _showCategoryForm(
    context,
    bloc: bloc,
    title: 'إضافة فئة رئيسية',
    operationKey: 'main_added',
    onSubmit: (nameAr, nameEn) =>
        bloc.add(MainCategoryCreateRequested(nameAr: nameAr, nameEn: nameEn)),
  );
}

void _editMain(
  BuildContext context,
  CategoryManagementBloc bloc,
  ManagedMainCategory category,
) {
  _showCategoryForm(
    context,
    bloc: bloc,
    title: 'تعديل فئة رئيسية',
    operationKey: 'main_updated',
    initialNameAr: category.nameAr,
    initialNameEn: category.nameEn,
    onSubmit: (nameAr, nameEn) => bloc.add(
      MainCategoryUpdateRequested(
        id: category.id,
        nameAr: nameAr,
        nameEn: nameEn,
      ),
    ),
  );
}

Future<void> _toggleMainActive(
  BuildContext context,
  CategoryManagementBloc bloc,
  ManagedMainCategory category,
) async {
  if (category.isActive) {
    final ok = await _confirmDeactivate(
      context,
      'إلغاء تفعيل الفئة الرئيسية',
      'لن تكون هذه الفئة متاحة للتصنيفات الجديدة، لكن المستندات القائمة ستظل '
          'تعرض اسمها. هل تريد المتابعة؟',
    );
    if (ok != true) return;
  }
  bloc.add(
    MainCategoryActiveSet(id: category.id, isActive: !category.isActive),
  );
}

void _addSub(
  BuildContext context,
  CategoryManagementBloc bloc,
  int mainCategoryId,
) {
  _showCategoryForm(
    context,
    bloc: bloc,
    title: 'إضافة فئة فرعية',
    operationKey: 'sub_added',
    onSubmit: (nameAr, nameEn) => bloc.add(
      SubCategoryCreateRequested(
        mainCategoryId: mainCategoryId,
        nameAr: nameAr,
        nameEn: nameEn,
      ),
    ),
  );
}

void _editSub(
  BuildContext context,
  CategoryManagementBloc bloc,
  ManagedSubCategory category,
) {
  _showCategoryForm(
    context,
    bloc: bloc,
    title: 'تعديل فئة فرعية',
    operationKey: 'sub_updated',
    initialNameAr: category.nameAr,
    initialNameEn: category.nameEn,
    onSubmit: (nameAr, nameEn) => bloc.add(
      SubCategoryUpdateRequested(
        id: category.id,
        nameAr: nameAr,
        nameEn: nameEn,
      ),
    ),
  );
}

Future<void> _toggleSubActive(
  BuildContext context,
  CategoryManagementBloc bloc,
  ManagedSubCategory category,
) async {
  if (category.isActive) {
    final ok = await _confirmDeactivate(
      context,
      'إلغاء تفعيل الفئة الفرعية',
      'لن تكون هذه الفئة الفرعية متاحة للتصنيفات الجديدة، لكن المستندات القائمة '
          'ستظل تعرض اسمها. هل تريد المتابعة؟',
    );
    if (ok != true) return;
  }
  bloc.add(SubCategoryActiveSet(id: category.id, isActive: !category.isActive));
}

Future<void> _moveSub(
  BuildContext context,
  CategoryManagementBloc bloc,
  CategoryManagementState state,
  ManagedSubCategory category,
) async {
  final targets = state.mainCategories
      .where((m) => m.isActive && m.id != category.mainCategoryId)
      .toList();
  if (targets.isEmpty) return;
  final targetId = await _showMoveDialog(context, targets);
  if (targetId == null) return;
  bloc.add(
    SubCategoryMoveRequested(
      subCategoryId: category.id,
      newMainCategoryId: targetId,
    ),
  );
}

Future<bool?> _confirmDeactivate(
  BuildContext context,
  String title,
  String body,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
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
}

/// Shows the add/edit form bound to [bloc]. The dialog stays open until the
/// operation succeeds, so on validation failure the entered values are
/// preserved and the friendly Arabic error is shown inline. Sort order is never
/// exposed; the repository places new categories automatically.
void _showCategoryForm(
  BuildContext context, {
  required CategoryManagementBloc bloc,
  required String title,
  required String operationKey,
  required void Function(String nameAr, String nameEn) onSubmit,
  String initialNameAr = '',
  String initialNameEn = '',
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => BlocProvider<CategoryManagementBloc>.value(
      value: bloc,
      child: _CategoryFormDialog(
        title: title,
        operationKey: operationKey,
        onSubmit: onSubmit,
        initialNameAr: initialNameAr,
        initialNameEn: initialNameEn,
      ),
    ),
  );
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.title,
    required this.operationKey,
    required this.onSubmit,
    required this.initialNameAr,
    required this.initialNameEn,
  });

  final String title;
  final String operationKey;
  final void Function(String nameAr, String nameEn) onSubmit;
  final String initialNameAr;
  final String initialNameEn;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _nameAr = TextEditingController(
    text: widget.initialNameAr,
  );
  late final TextEditingController _nameEn = TextEditingController(
    text: widget.initialNameEn,
  );

  String? _arError;
  String? _enError;
  String? _formError;
  bool _submitting = false;
  int? _baselineOpSeq;

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    super.dispose();
  }

  /// Instant client-side check mirroring the service rules, so obviously
  /// invalid input never leaves the dialog and the entered text is kept.
  String? _fieldError(String raw, {required bool isArabic}) {
    if (categoryNameHasForbiddenCharacters(raw)) {
      return isArabic
          ? 'يحتوي الاسم العربي على رموز تحكم أو محارف غير مرئية غير مسموح بها.'
          : 'يحتوي الاسم الإنجليزي على رموز تحكم أو محارف غير مرئية غير مسموح بها.';
    }
    final String cleaned = cleanCategoryDisplayName(raw);
    if (cleaned.isEmpty) {
      return isArabic ? 'الاسم العربي مطلوب.' : 'الاسم الإنجليزي مطلوب.';
    }
    if (cleaned.length > CategoryManagementService.maxNameLength) {
      return 'الاسم يتجاوز الحد المسموح من الأحرف.';
    }
    if (isArabic) {
      if (categoryNameHasLatinLetter(cleaned)) {
        return categoryArabicScriptOnlyMessage;
      }
      if (!categoryNameHasArabicLetter(cleaned)) {
        return categoryArabicScriptRequiredMessage;
      }
    } else {
      if (categoryNameHasArabicLetter(cleaned)) {
        return categoryLatinScriptOnlyMessage;
      }
      if (!categoryNameHasLatinLetter(cleaned)) {
        return categoryLatinScriptRequiredMessage;
      }
    }
    return null;
  }

  void _submit() {
    final String rawAr = _nameAr.text;
    final String rawEn = _nameEn.text;
    final String? arError = _fieldError(rawAr, isArabic: true);
    final String? enError = _fieldError(rawEn, isArabic: false);
    if (arError != null || enError != null) {
      setState(() {
        _arError = arError;
        _enError = enError;
        _formError = null;
      });
      return;
    }
    setState(() {
      _arError = null;
      _enError = null;
      _formError = null;
      _submitting = true;
      _baselineOpSeq = context.read<CategoryManagementBloc>().state.opSeq;
    });
    widget.onSubmit(
      cleanCategoryDisplayName(rawAr),
      cleanCategoryDisplayName(rawEn),
    );
  }

  void _onState(BuildContext context, CategoryManagementState state) {
    if (!_submitting) return;
    final int? baseline = _baselineOpSeq;
    if (baseline != null && state.opSeq <= baseline) return;
    if (state.lastOperationKey != widget.operationKey) return;
    switch (state.lastOutcome) {
      case CategoryOpOutcome.success:
        Navigator.of(context).pop();
        break;
      case CategoryOpOutcome.validationFailure:
        String? arError;
        String? enError;
        String? formError;
        for (final error in state.validationErrors) {
          final String message = categoryErrorMessage(error);
          if (error.field == 'nameAr') {
            arError = message;
          } else if (error.field == 'nameEn') {
            enError = message;
          } else {
            formError = message;
          }
        }
        if (arError == null && enError == null && formError == null) {
          formError = categoryUnexpectedErrorMessage;
        }
        setState(() {
          _submitting = false;
          _arError = arError;
          _enError = enError;
          _formError = formError;
        });
        break;
      case CategoryOpOutcome.error:
        setState(() {
          _submitting = false;
          _formError = categoryUnexpectedErrorMessage;
        });
        break;
      case CategoryOpOutcome.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CategoryManagementBloc, CategoryManagementState>(
      listenWhen: (p, c) => p.opSeq != c.opSeq,
      listener: _onState,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('category_dialog_name_ar'),
                controller: _nameAr,
                decoration: InputDecoration(
                  labelText: 'الاسم بالعربية',
                  errorText: _arError,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('category_dialog_name_en'),
                controller: _nameEn,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'الاسم بالإنجليزية',
                  errorText: _enError,
                ),
              ),
              if (_formError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _formError!,
                  key: const Key('category_dialog_form_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('category_dialog_submit'),
            onPressed: _submitting ? null : _submit,
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

Future<int?> _showMoveDialog(
  BuildContext context,
  List<ManagedMainCategory> targets,
) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => _MoveDialog(targets: targets),
  );
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.targets});

  final List<ManagedMainCategory> targets;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  int? _targetId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('نقل الفئة الفرعية'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'يُسمح بالنقل فقط للفئات الفرعية غير المستخدمة في أي مستند. '
              'اختر الفئة الرئيسية الجديدة:',
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              key: const Key('category_move_target'),
              initialValue: _targetId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الفئة الرئيسية'),
              items: [
                for (final m in widget.targets)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(m.nameAr, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _targetId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('category_move_submit'),
          onPressed: _targetId == null
              ? null
              : () => Navigator.of(context).pop(_targetId),
          child: const Text('نقل'),
        ),
      ],
    );
  }
}
