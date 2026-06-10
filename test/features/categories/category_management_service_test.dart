import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/categories/domain/repositories/category_management_repository.dart';
import 'package:legal_library_manager/features/categories/domain/services/category_key_generator.dart';
import 'package:legal_library_manager/features/categories/domain/services/category_management_service.dart';

void main() {
  group('CategoryManagementService', () {
    late _FakeRepository repository;
    late CategoryManagementService service;

    setUp(() {
      repository = _FakeRepository();
      service = CategoryManagementService(
        repository: repository,
        keyGenerator: _FixedKeyGenerator(),
      );
    });

    test('rejects blank names before writing', () async {
      final result = await service.addMainCategory(nameAr: ' ', nameEn: '');

      expect(result.isInvalid, isTrue);
      expect(
        result.errors.map((e) => e.field),
        containsAll(['nameAr', 'nameEn']),
      );
      expect(repository.insertMainCalls, 0);
    });

    test('rejects names with invisible formatting characters', () async {
      final result = await service.addMainCategory(
        nameAr: 'فئة${String.fromCharCode(0x200B)}',
        nameEn: 'Category',
      );

      expect(result.isInvalid, isTrue);
      expect(result.errors.any((e) => e.code == 'invalid_chars'), isTrue);
      expect(repository.insertMainCalls, 0);
    });

    test('accepts genuine Arabic and English names', () async {
      for (final pair in const [
        ('القانون العام', 'Public Law'),
        ('القانون رقم 12', 'Law No. 12'),
        ('القانون العام (1)', 'Public Law (1)'),
        ('القانون الإداري-المالي', 'Administrative-Financial Law'),
      ]) {
        repository = _FakeRepository();
        service = CategoryManagementService(
          repository: repository,
          keyGenerator: _FixedKeyGenerator(),
        );
        final result = await service.addMainCategory(
          nameAr: pair.$1,
          nameEn: pair.$2,
        );
        expect(result.isValid, isTrue, reason: '${pair.$1} / ${pair.$2}');
        expect(repository.insertMainCalls, 1);
      }
    });

    test('rejects an Arabic field that contains Latin letters', () async {
      final result = await service.addMainCategory(
        nameAr: 'القانون Public',
        nameEn: 'Public Law',
      );

      expect(result.isInvalid, isTrue);
      expect(
        result.errors.singleWhere((e) => e.field == 'nameAr').code,
        'arabic_script_only',
      );
      expect(repository.insertMainCalls, 0);
    });

    test('rejects an Arabic field with no Arabic letter', () async {
      final result = await service.addMainCategory(
        nameAr: '12345',
        nameEn: 'Public Law',
      );

      expect(
        result.errors.singleWhere((e) => e.field == 'nameAr').code,
        'arabic_script_required',
      );
      expect(repository.insertMainCalls, 0);
    });

    test('rejects an English field that contains Arabic letters', () async {
      final result = await service.addMainCategory(
        nameAr: 'القانون العام',
        nameEn: 'Public القانون',
      );

      expect(
        result.errors.singleWhere((e) => e.field == 'nameEn').code,
        'latin_script_only',
      );
      expect(repository.insertMainCalls, 0);
    });

    test('rejects an English field with no Latin letter', () async {
      final result = await service.addMainCategory(
        nameAr: 'القانون العام',
        nameEn: '12345',
      );

      expect(
        result.errors.singleWhere((e) => e.field == 'nameEn').code,
        'latin_script_required',
      );
      expect(repository.insertMainCalls, 0);
    });

    test('applies the same script rules to subcategories', () async {
      final result = await service.addSubCategory(
        mainCategoryId: 1,
        nameAr: 'Public Law',
        nameEn: 'القانون العام',
      );

      expect(result.hasCode('arabic_script_only'), isTrue);
      expect(result.hasCode('latin_script_only'), isTrue);
    });

    test('forbidden characters take priority over script rules', () async {
      final result = await service.addMainCategory(
        nameAr: 'Public${String.fromCharCode(0x200B)}',
        nameEn: 'Public Law',
      );

      // The single Arabic-field error is the forbidden-character one, not a
      // script error, since forbidden characters are checked first.
      final arError = result.errors.singleWhere((e) => e.field == 'nameAr');
      expect(arError.code, 'invalid_chars');
    });

    test('cleans whitespace before delegating to the repository', () async {
      await service.addMainCategory(
        nameAr: '  فئة   جديدة ',
        nameEn: '  New   Category ',
      );

      expect(repository.lastMainAr, 'فئة جديدة');
      expect(repository.lastMainEn, 'New Category');
    });

    test('maps duplicate names to structured validation errors', () async {
      repository.insertMainError = const DuplicateCategoryNameException(
        'nameAr',
      );

      final result = await service.addMainCategory(
        nameAr: 'فئة',
        nameEn: 'Category',
      );

      expect(result.isInvalid, isTrue);
      expect(result.errors.single.field, 'nameAr');
      expect(result.errors.single.code, 'duplicate');
    });

    test('maps a used-subcategory move to a safe validation error', () async {
      repository.moveError = const SubCategoryInUseException();

      final result = await service.moveSubCategory(
        subCategoryId: 1,
        newMainCategoryId: 2,
      );

      expect(result.isInvalid, isTrue);
      expect(result.errors.single.code, 'in_use');
    });

    test('generated keys are supplied only when creating categories', () async {
      expect(
        (await service.addMainCategory(
          nameAr: 'فئة',
          nameEn: 'Category',
        )).isValid,
        isTrue,
      );
      expect(
        (await service.addSubCategory(
          mainCategoryId: 1,
          nameAr: 'فرعية',
          nameEn: 'Subcategory',
        )).isValid,
        isTrue,
      );

      expect(repository.lastMainKey, 'usr_main_fixed');
      expect(repository.lastSubKey, 'usr_sub_fixed');
    });

    test('reorder delegates to the repository and returns valid', () async {
      final result = await service.reorderMainCategory(idA: 1, idB: 2);
      expect(result.isValid, isTrue);
      expect(repository.lastReorderMainIdA, 1);
      expect(repository.lastReorderMainIdB, 2);
    });
  });
}

class _FixedKeyGenerator implements CategoryKeyGenerator {
  @override
  String mainCategoryKey() => 'usr_main_fixed';

  @override
  String subCategoryKey() => 'usr_sub_fixed';
}

class _FakeRepository implements CategoryManagementRepository {
  int insertMainCalls = 0;
  String? lastMainKey;
  String? lastMainAr;
  String? lastMainEn;
  String? lastSubKey;
  int? lastReorderMainIdA;
  int? lastReorderMainIdB;
  Object? insertMainError;
  Object? moveError;

  @override
  Future<int> insertMainCategory({
    required String key,
    required String nameAr,
    required String nameEn,
  }) async {
    insertMainCalls++;
    lastMainKey = key;
    lastMainAr = nameAr;
    lastMainEn = nameEn;
    if (insertMainError case final error?) throw error;
    return 1;
  }

  @override
  Future<int> insertSubCategory({
    required int mainCategoryId,
    required String key,
    required String nameAr,
    required String nameEn,
  }) async {
    lastSubKey = key;
    return 1;
  }

  @override
  Future<void> moveSubCategory({
    required int subCategoryId,
    required int newMainCategoryId,
  }) async {
    if (moveError case final error?) throw error;
  }

  @override
  Future<void> reorderMainCategory({required int idA, required int idB}) async {
    lastReorderMainIdA = idA;
    lastReorderMainIdB = idB;
  }

  @override
  Future<void> reorderSubCategory({required int idA, required int idB}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by this test');
}
