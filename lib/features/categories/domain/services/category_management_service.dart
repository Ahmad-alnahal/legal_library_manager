// lib/features/categories/domain/services/category_management_service.dart

import '../../../../core/validation/validation_error.dart';
import '../../../../core/validation/validation_result.dart';
import '../repositories/category_management_repository.dart';
import 'category_key_generator.dart';
import 'category_name.dart';

/// Validates and applies category-management operations.
///
/// Input rules (forbidden characters, blank-after-cleaning, length) are enforced
/// here on the human-readable display names; cross-row integrity rules
/// (normalized-name uniqueness, "unused before move", key uniqueness) are
/// enforced transactionally by the repository, which signals them via typed
/// exceptions that this service maps to a structured [ValidationResult]. Display
/// names are cleaned (trim + whitespace collapse) before persistence; the
/// repository derives and stores the matching normalized comparison values.
/// Sort order is managed entirely by the repository; callers never supply or
/// edit numeric positions. The service never deletes anything and never touches
/// files.
class CategoryManagementService {
  CategoryManagementService({
    required this.repository,
    required this.keyGenerator,
  });

  final CategoryManagementRepository repository;
  final CategoryKeyGenerator keyGenerator;

  /// Maximum number of characters allowed in a display name (post-clean).
  static const int maxNameLength = 200;

  /// Number of key regenerations attempted if a generated key collides.
  static const int _keyRetries = 5;

  // --- main categories ---

  Future<ValidationResult> addMainCategory({
    required String nameAr,
    required String nameEn,
  }) async {
    final _NameCheck check = _validateNames(nameAr, nameEn);
    if (check.result.isInvalid) return check.result;

    return _withKeyRetries((key) async {
      await repository.insertMainCategory(
        key: key,
        nameAr: check.ar,
        nameEn: check.en,
      );
    }, keyGenerator.mainCategoryKey);
  }

  Future<ValidationResult> editMainCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  }) async {
    final _NameCheck check = _validateNames(nameAr, nameEn);
    if (check.result.isInvalid) return check.result;
    try {
      await repository.updateMainCategory(
        id: id,
        nameAr: check.ar,
        nameEn: check.en,
      );
      return const ValidationResult.valid();
    } on DuplicateCategoryNameException catch (e) {
      return _duplicate(e.field);
    }
  }

  Future<ValidationResult> setMainCategoryActive(
    int id, {
    required bool isActive,
  }) async {
    await repository.setMainCategoryActive(id, isActive: isActive);
    return const ValidationResult.valid();
  }

  Future<ValidationResult> reorderMainCategory({
    required int idA,
    required int idB,
  }) async {
    await repository.reorderMainCategory(idA: idA, idB: idB);
    return const ValidationResult.valid();
  }

  // --- subcategories ---

  Future<ValidationResult> addSubCategory({
    required int mainCategoryId,
    required String nameAr,
    required String nameEn,
  }) async {
    final _NameCheck check = _validateNames(nameAr, nameEn);
    if (check.result.isInvalid) return check.result;

    return _withKeyRetries((key) async {
      await repository.insertSubCategory(
        mainCategoryId: mainCategoryId,
        key: key,
        nameAr: check.ar,
        nameEn: check.en,
      );
    }, keyGenerator.subCategoryKey);
  }

  Future<ValidationResult> editSubCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  }) async {
    final _NameCheck check = _validateNames(nameAr, nameEn);
    if (check.result.isInvalid) return check.result;
    try {
      await repository.updateSubCategory(
        id: id,
        nameAr: check.ar,
        nameEn: check.en,
      );
      return const ValidationResult.valid();
    } on DuplicateCategoryNameException catch (e) {
      return _duplicate(e.field);
    }
  }

  Future<ValidationResult> setSubCategoryActive(
    int id, {
    required bool isActive,
  }) async {
    await repository.setSubCategoryActive(id, isActive: isActive);
    return const ValidationResult.valid();
  }

  Future<ValidationResult> reorderSubCategory({
    required int idA,
    required int idB,
  }) async {
    await repository.reorderSubCategory(idA: idA, idB: idB);
    return const ValidationResult.valid();
  }

  Future<ValidationResult> moveSubCategory({
    required int subCategoryId,
    required int newMainCategoryId,
  }) async {
    try {
      await repository.moveSubCategory(
        subCategoryId: subCategoryId,
        newMainCategoryId: newMainCategoryId,
      );
      return const ValidationResult.valid();
    } on SubCategoryInUseException {
      return ValidationResult([
        const ValidationError(
          field: 'move',
          code: 'in_use',
          message: 'Subcategory is referenced and cannot be moved.',
        ),
      ]);
    } on DuplicateCategoryNameException catch (e) {
      return _duplicate(e.field);
    } on InactiveMainCategoryException {
      return _inactiveParent();
    }
  }

  // --- internals ---

  /// Validates both display names and returns the cleaned values to persist.
  /// The Arabic field must use Arabic script and the English field Latin
  /// script; each is checked against its expected writing system.
  _NameCheck _validateNames(String rawAr, String rawEn) {
    final builder = ValidationErrorBuilder();
    final String ar = _checkName(builder, 'nameAr', rawAr, _NameScript.arabic);
    final String en = _checkName(builder, 'nameEn', rawEn, _NameScript.latin);
    return (result: builder.build(), ar: ar, en: en);
  }

  /// Validates one display name and returns its cleaned form. Forbidden
  /// characters are checked on the raw input (before cleaning) so newline/tab
  /// cannot be silently folded into a space. Checks run cheapest-and-most-
  /// fundamental first and stop at the first failure, so a single, most useful
  /// error is reported per field: forbidden characters, then required, then
  /// length, then the writing-system rules.
  String _checkName(
    ValidationErrorBuilder builder,
    String field,
    String raw,
    _NameScript script,
  ) {
    final String cleaned = cleanCategoryDisplayName(raw);
    if (categoryNameHasForbiddenCharacters(raw)) {
      builder.add(
        field,
        'invalid_chars',
        '$field contains control or invisible formatting characters.',
      );
      return cleaned;
    }
    if (cleaned.isEmpty) {
      builder.add(field, 'required', '$field is required.');
      return cleaned;
    }
    if (cleaned.length > maxNameLength) {
      builder.add(field, 'too_long', '$field is too long.');
      return cleaned;
    }
    _addScriptError(builder, field, cleaned, script);
    return cleaned;
  }

  /// Enforces the writing-system rule for [cleaned]: the wrong-script-letter
  /// check runs before the missing-script-letter check so that mixed or
  /// wrong-language input gets the more specific "must use only this script"
  /// message. At most one error is added.
  void _addScriptError(
    ValidationErrorBuilder builder,
    String field,
    String cleaned,
    _NameScript script,
  ) {
    switch (script) {
      case _NameScript.arabic:
        if (categoryNameHasLatinLetter(cleaned)) {
          builder.add(
            field,
            'arabic_script_only',
            '$field must not contain Latin letters.',
          );
        } else if (!categoryNameHasArabicLetter(cleaned)) {
          builder.add(
            field,
            'arabic_script_required',
            '$field must contain at least one Arabic letter.',
          );
        }
      case _NameScript.latin:
        if (categoryNameHasArabicLetter(cleaned)) {
          builder.add(
            field,
            'latin_script_only',
            '$field must not contain Arabic letters.',
          );
        } else if (!categoryNameHasLatinLetter(cleaned)) {
          builder.add(
            field,
            'latin_script_required',
            '$field must contain at least one Latin letter.',
          );
        }
    }
  }

  ValidationResult _duplicate(String field) => ValidationResult([
    ValidationError(
      field: field,
      code: 'duplicate',
      message: 'A category with this name already exists.',
    ),
  ]);

  ValidationResult _inactiveParent() => ValidationResult([
    const ValidationError(
      field: 'mainCategoryId',
      code: 'inactive',
      message: 'The target main category is inactive.',
    ),
  ]);

  /// Runs an insert that needs a generated key, regenerating and retrying on a
  /// key collision. Maps duplicate-name violations to a [ValidationResult].
  Future<ValidationResult> _withKeyRetries(
    Future<void> Function(String key) insert,
    String Function() generateKey,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await insert(generateKey());
        return const ValidationResult.valid();
      } on DuplicateCategoryNameException catch (e) {
        return _duplicate(e.field);
      } on CategoryKeyCollisionException {
        if (attempt >= _keyRetries) rethrow;
        // else regenerate a new key and retry.
      } on InactiveMainCategoryException {
        return _inactiveParent();
      }
    }
  }
}

/// The result of validating a display-name pair plus the cleaned values to
/// persist when valid.
typedef _NameCheck = ({ValidationResult result, String ar, String en});

/// The writing system a category-name field is required to use.
enum _NameScript { arabic, latin }
