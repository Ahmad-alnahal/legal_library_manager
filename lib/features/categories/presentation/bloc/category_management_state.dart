// lib/features/categories/presentation/bloc/category_management_state.dart

import 'package:equatable/equatable.dart';

import '../../../../core/validation/validation_error.dart';
import '../../domain/entities/managed_main_category.dart';
import '../../domain/entities/managed_sub_category.dart';

enum CategoryLoadStatus { initial, loading, success, failure }

/// The outcome of the most recently completed mutation, used to drive one-shot
/// UI feedback (snackbars / inline messages).
enum CategoryOpOutcome { none, success, validationFailure, error }

class CategoryManagementState extends Equatable {
  const CategoryManagementState({
    this.loadStatus = CategoryLoadStatus.initial,
    this.mainCategories = const [],
    this.subCategories = const [],
    this.selectedMainCategoryId,
    this.showInactive = true,
    this.isBusy = false,
    this.opSeq = 0,
    this.lastOutcome = CategoryOpOutcome.none,
    this.lastOperationKey,
    this.validationErrors = const [],
  });

  final CategoryLoadStatus loadStatus;

  /// All main categories (active + inactive), ordered.
  final List<ManagedMainCategory> mainCategories;

  /// All subcategories (active + inactive), ordered.
  final List<ManagedSubCategory> subCategories;

  /// The main category whose subcategories are shown, or null.
  final int? selectedMainCategoryId;

  /// Whether inactive categories are included in the displayed lists.
  final bool showInactive;

  /// True while a mutation is in flight (prevents overlapping operations).
  final bool isBusy;

  /// Increments whenever an operation completes; lets the page react once.
  final int opSeq;
  final CategoryOpOutcome lastOutcome;

  /// A stable key describing the last operation (e.g. `main_added`), for
  /// success/feedback messaging. Never a raw error string.
  final String? lastOperationKey;

  /// Structured validation errors from the last failed mutation.
  final List<ValidationError> validationErrors;

  /// Subcategories under [selectedMainCategoryId].
  List<ManagedSubCategory> get subCategoriesForSelected {
    final id = selectedMainCategoryId;
    if (id == null) return const [];
    return subCategories
        .where((s) => s.mainCategoryId == id)
        .toList(growable: false);
  }

  CategoryManagementState copyWith({
    CategoryLoadStatus? loadStatus,
    List<ManagedMainCategory>? mainCategories,
    List<ManagedSubCategory>? subCategories,
    int? selectedMainCategoryId,
    bool clearSelectedMain = false,
    bool? showInactive,
    bool? isBusy,
    int? opSeq,
    CategoryOpOutcome? lastOutcome,
    String? lastOperationKey,
    bool clearOperationKey = false,
    List<ValidationError>? validationErrors,
  }) {
    return CategoryManagementState(
      loadStatus: loadStatus ?? this.loadStatus,
      mainCategories: mainCategories ?? this.mainCategories,
      subCategories: subCategories ?? this.subCategories,
      selectedMainCategoryId: clearSelectedMain
          ? null
          : selectedMainCategoryId ?? this.selectedMainCategoryId,
      showInactive: showInactive ?? this.showInactive,
      isBusy: isBusy ?? this.isBusy,
      opSeq: opSeq ?? this.opSeq,
      lastOutcome: lastOutcome ?? this.lastOutcome,
      lastOperationKey: clearOperationKey
          ? null
          : lastOperationKey ?? this.lastOperationKey,
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }

  @override
  List<Object?> get props => [
    loadStatus,
    mainCategories,
    subCategories,
    selectedMainCategoryId,
    showInactive,
    isBusy,
    opSeq,
    lastOutcome,
    lastOperationKey,
    validationErrors,
  ];
}
