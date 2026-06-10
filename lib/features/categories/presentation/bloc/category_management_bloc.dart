// lib/features/categories/presentation/bloc/category_management_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/validation/validation_result.dart';
import '../../domain/entities/managed_main_category.dart';
import '../../domain/entities/managed_sub_category.dart';
import '../../domain/repositories/category_management_repository.dart';
import '../../domain/services/category_management_service.dart';
import 'category_management_event.dart';
import 'category_management_state.dart';

/// Drives the Category Management workspace: loads main categories and
/// subcategories, and applies validated, non-destructive mutations through the
/// [CategoryManagementService]. Holds no persistence types.
class CategoryManagementBloc
    extends Bloc<CategoryManagementEvent, CategoryManagementState> {
  CategoryManagementBloc({required this.repository, required this.service})
    : super(const CategoryManagementState()) {
    on<CategoryManagementStarted>(_onStarted);
    on<CategoryManagementRetryRequested>(_onStarted);
    on<CategoryMainSelected>(_onMainSelected);
    on<CategoryShowInactiveToggled>(_onShowInactiveToggled);
    on<MainCategoryCreateRequested>(_onMainCreate);
    on<MainCategoryUpdateRequested>(_onMainUpdate);
    on<MainCategoryActiveSet>(_onMainActiveSet);
    on<MainCategoryReorderRequested>(_onMainReorder);
    on<SubCategoryCreateRequested>(_onSubCreate);
    on<SubCategoryUpdateRequested>(_onSubUpdate);
    on<SubCategoryActiveSet>(_onSubActiveSet);
    on<SubCategoryReorderRequested>(_onSubReorder);
    on<SubCategoryMoveRequested>(_onSubMove);
  }

  final CategoryManagementRepository repository;
  final CategoryManagementService service;

  Future<void> _onStarted(
    CategoryManagementEvent event,
    Emitter<CategoryManagementState> emit,
  ) async {
    emit(state.copyWith(loadStatus: CategoryLoadStatus.loading));
    try {
      final mains = await repository.getMainCategories();
      final subs = await repository.getSubCategories();
      int? selected = state.selectedMainCategoryId;
      if (selected == null || !mains.any((m) => m.id == selected)) {
        selected = mains.isEmpty ? null : mains.first.id;
      }
      emit(
        state.copyWith(
          loadStatus: CategoryLoadStatus.success,
          mainCategories: mains,
          subCategories: subs,
          selectedMainCategoryId: selected,
          clearSelectedMain: selected == null,
        ),
      );
    } catch (_) {
      emit(state.copyWith(loadStatus: CategoryLoadStatus.failure));
    }
  }

  void _onMainSelected(
    CategoryMainSelected event,
    Emitter<CategoryManagementState> emit,
  ) {
    emit(
      state.copyWith(
        selectedMainCategoryId: event.mainCategoryId,
        clearSelectedMain: event.mainCategoryId == null,
      ),
    );
  }

  void _onShowInactiveToggled(
    CategoryShowInactiveToggled event,
    Emitter<CategoryManagementState> emit,
  ) {
    emit(state.copyWith(showInactive: event.showInactive));
  }

  Future<void> _onMainCreate(
    MainCategoryCreateRequested event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      'main_added',
      () => service.addMainCategory(nameAr: event.nameAr, nameEn: event.nameEn),
    );
  }

  Future<void> _onMainUpdate(
    MainCategoryUpdateRequested event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      'main_updated',
      () => service.editMainCategory(
        id: event.id,
        nameAr: event.nameAr,
        nameEn: event.nameEn,
      ),
    );
  }

  Future<void> _onMainActiveSet(
    MainCategoryActiveSet event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      event.isActive ? 'main_activated' : 'main_deactivated',
      () => service.setMainCategoryActive(event.id, isActive: event.isActive),
    );
  }

  Future<void> _onMainReorder(
    MainCategoryReorderRequested event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      'main_reordered',
      () => service.reorderMainCategory(idA: event.idA, idB: event.idB),
    );
  }

  Future<void> _onSubCreate(
    SubCategoryCreateRequested event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      'sub_added',
      () => service.addSubCategory(
        mainCategoryId: event.mainCategoryId,
        nameAr: event.nameAr,
        nameEn: event.nameEn,
      ),
    );
  }

  Future<void> _onSubUpdate(
    SubCategoryUpdateRequested event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      'sub_updated',
      () => service.editSubCategory(
        id: event.id,
        nameAr: event.nameAr,
        nameEn: event.nameEn,
      ),
    );
  }

  Future<void> _onSubActiveSet(
    SubCategoryActiveSet event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      event.isActive ? 'sub_activated' : 'sub_deactivated',
      () => service.setSubCategoryActive(event.id, isActive: event.isActive),
    );
  }

  Future<void> _onSubReorder(
    SubCategoryReorderRequested event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      'sub_reordered',
      () => service.reorderSubCategory(idA: event.idA, idB: event.idB),
    );
  }

  Future<void> _onSubMove(
    SubCategoryMoveRequested event,
    Emitter<CategoryManagementState> emit,
  ) {
    return _runMutation(
      emit,
      'sub_moved',
      () => service.moveSubCategory(
        subCategoryId: event.subCategoryId,
        newMainCategoryId: event.newMainCategoryId,
      ),
    );
  }

  /// Runs a single mutation with overlap protection, surfaces validation/error
  /// outcomes via a one-shot [CategoryManagementState.opSeq] bump, and reloads
  /// the lists after a successful change so the UI reflects it immediately.
  Future<void> _runMutation(
    Emitter<CategoryManagementState> emit,
    String operationKey,
    Future<ValidationResult> Function() action,
  ) async {
    if (state.isBusy) return;
    emit(state.copyWith(isBusy: true, validationErrors: const []));
    try {
      final result = await action();
      if (result.isInvalid) {
        emit(
          state.copyWith(
            isBusy: false,
            opSeq: state.opSeq + 1,
            lastOutcome: CategoryOpOutcome.validationFailure,
            lastOperationKey: operationKey,
            validationErrors: result.errors,
          ),
        );
        return;
      }
      final mains = await repository.getMainCategories();
      final subs = await repository.getSubCategories();
      int? selected = state.selectedMainCategoryId;
      if (selected != null && !mains.any((m) => m.id == selected)) {
        selected = mains.isEmpty ? null : mains.first.id;
      }
      emit(
        state.copyWith(
          loadStatus: CategoryLoadStatus.success,
          mainCategories: mains,
          subCategories: subs,
          selectedMainCategoryId: selected,
          clearSelectedMain: selected == null,
          isBusy: false,
          opSeq: state.opSeq + 1,
          lastOutcome: CategoryOpOutcome.success,
          lastOperationKey: operationKey,
          validationErrors: const [],
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isBusy: false,
          opSeq: state.opSeq + 1,
          lastOutcome: CategoryOpOutcome.error,
          lastOperationKey: operationKey,
          validationErrors: const [],
        ),
      );
    }
  }

  // Re-exported for tests/readability.
  static List<ManagedMainCategory> activeOnly(List<ManagedMainCategory> all) =>
      all.where((m) => m.isActive).toList(growable: false);

  static List<ManagedSubCategory> activeSubsOnly(
    List<ManagedSubCategory> all,
  ) => all.where((s) => s.isActive).toList(growable: false);
}
