import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/categories/domain/entities/managed_main_category.dart';
import 'package:legal_library_manager/features/categories/domain/entities/managed_sub_category.dart';
import 'package:legal_library_manager/features/categories/domain/repositories/category_management_repository.dart';
import 'package:legal_library_manager/features/categories/domain/services/category_key_generator.dart';
import 'package:legal_library_manager/features/categories/domain/services/category_management_service.dart';
import 'package:legal_library_manager/features/categories/presentation/bloc/category_management_bloc.dart';
import 'package:legal_library_manager/features/categories/presentation/bloc/category_management_event.dart';
import 'package:legal_library_manager/features/categories/presentation/bloc/category_management_state.dart';

void main() {
  group('CategoryManagementBloc', () {
    late _MemoryCategoryRepository repository;
    late CategoryManagementBloc bloc;

    setUp(() {
      repository = _MemoryCategoryRepository();
      bloc = CategoryManagementBloc(
        repository: repository,
        service: CategoryManagementService(
          repository: repository,
          keyGenerator: _SequenceKeyGenerator(),
        ),
      );
    });

    tearDown(() => bloc.close());

    test(
      'loads active and inactive categories and selects the first main',
      () async {
        bloc.add(const CategoryManagementStarted());
        await _waitFor(
          bloc,
          (state) => state.loadStatus == CategoryLoadStatus.success,
        );

        expect(bloc.state.mainCategories.length, 2);
        expect(bloc.state.subCategories.length, 1);
        expect(bloc.state.selectedMainCategoryId, 1);
      },
    );

    test('successful add reloads lists and reports a safe outcome', () async {
      bloc.add(const CategoryManagementStarted());
      await _waitFor(
        bloc,
        (state) => state.loadStatus == CategoryLoadStatus.success,
      );

      bloc.add(
        const MainCategoryCreateRequested(
          nameAr: 'فئة جديدة',
          nameEn: 'New Category',
        ),
      );
      await _waitFor(bloc, (state) => state.opSeq == 1);

      expect(bloc.state.lastOutcome, CategoryOpOutcome.success);
      expect(bloc.state.lastOperationKey, 'main_added');
      expect(
        bloc.state.mainCategories.any((m) => m.nameEn == 'New Category'),
        isTrue,
      );
    });

    test(
      'validation failure is surfaced without losing loaded lists',
      () async {
        bloc.add(const CategoryManagementStarted());
        await _waitFor(
          bloc,
          (state) => state.loadStatus == CategoryLoadStatus.success,
        );

        bloc.add(const MainCategoryCreateRequested(nameAr: ' ', nameEn: ''));
        await _waitFor(bloc, (state) => state.opSeq == 1);

        expect(bloc.state.lastOutcome, CategoryOpOutcome.validationFailure);
        expect(bloc.state.validationErrors, isNotEmpty);
        expect(bloc.state.mainCategories.length, 2);
      },
    );

    test(
      'inactive visibility and selected-main filtering are state-driven',
      () async {
        bloc.add(const CategoryManagementStarted());
        await _waitFor(
          bloc,
          (state) => state.loadStatus == CategoryLoadStatus.success,
        );

        bloc
          ..add(const CategoryShowInactiveToggled(false))
          ..add(const CategoryMainSelected(2));
        await _waitFor(bloc, (state) => state.selectedMainCategoryId == 2);

        expect(bloc.state.showInactive, isFalse);
        expect(bloc.state.subCategoriesForSelected, isEmpty);
      },
    );

    test('invalid-character input surfaces a validation failure', () async {
      bloc.add(const CategoryManagementStarted());
      await _waitFor(
        bloc,
        (state) => state.loadStatus == CategoryLoadStatus.success,
      );

      bloc.add(
        MainCategoryCreateRequested(
          nameAr: 'فئة${String.fromCharCode(0x200B)}مخفية',
          nameEn: 'Valid Name',
        ),
      );
      await _waitFor(bloc, (state) => state.opSeq == 1);

      expect(bloc.state.lastOutcome, CategoryOpOutcome.validationFailure);
      expect(
        bloc.state.validationErrors.any((e) => e.code == 'invalid_chars'),
        isTrue,
      );
      // The list is untouched and nothing was inserted.
      expect(bloc.state.mainCategories.length, 2);
    });

    test('wrong-script names surface a validation failure', () async {
      bloc.add(const CategoryManagementStarted());
      await _waitFor(
        bloc,
        (state) => state.loadStatus == CategoryLoadStatus.success,
      );

      bloc.add(
        const MainCategoryCreateRequested(
          nameAr: 'Public Law',
          nameEn: 'القانون العام',
        ),
      );
      await _waitFor(bloc, (state) => state.opSeq == 1);

      expect(bloc.state.lastOutcome, CategoryOpOutcome.validationFailure);
      expect(
        bloc.state.validationErrors.any((e) => e.code == 'arabic_script_only'),
        isTrue,
      );
      expect(
        bloc.state.validationErrors.any((e) => e.code == 'latin_script_only'),
        isTrue,
      );
      // Nothing was inserted; the loaded list is untouched.
      expect(bloc.state.mainCategories.length, 2);
    });

    test('used-subcategory move rejection is a validation outcome', () async {
      repository.rejectMovesAsUsed = true;
      bloc.add(const CategoryManagementStarted());
      await _waitFor(
        bloc,
        (state) => state.loadStatus == CategoryLoadStatus.success,
      );

      bloc.add(
        const SubCategoryMoveRequested(subCategoryId: 10, newMainCategoryId: 2),
      );
      await _waitFor(bloc, (state) => state.opSeq == 1);

      expect(bloc.state.lastOutcome, CategoryOpOutcome.validationFailure);
      expect(bloc.state.validationErrors.single.code, 'in_use');
    });

    test('reorder main categories succeeds and reloads lists', () async {
      bloc.add(const CategoryManagementStarted());
      await _waitFor(
        bloc,
        (state) => state.loadStatus == CategoryLoadStatus.success,
      );

      bloc.add(const MainCategoryReorderRequested(idA: 1, idB: 2));
      await _waitFor(bloc, (state) => state.opSeq == 1);

      expect(bloc.state.lastOutcome, CategoryOpOutcome.success);
      expect(bloc.state.lastOperationKey, 'main_reordered');
      // Lists are reloaded after a successful reorder.
      expect(bloc.state.mainCategories.length, 2);
    });

    test('reorder subcategories succeeds and reloads lists', () async {
      bloc.add(const CategoryManagementStarted());
      await _waitFor(
        bloc,
        (state) => state.loadStatus == CategoryLoadStatus.success,
      );

      bloc.add(const SubCategoryReorderRequested(idA: 10, idB: 10));
      await _waitFor(bloc, (state) => state.opSeq == 1);

      expect(bloc.state.lastOutcome, CategoryOpOutcome.success);
      expect(bloc.state.lastOperationKey, 'sub_reordered');
    });
  });
}

Future<void> _waitFor(
  CategoryManagementBloc bloc,
  bool Function(CategoryManagementState state) predicate,
) async {
  if (predicate(bloc.state)) return;
  await bloc.stream.firstWhere(predicate).timeout(const Duration(seconds: 3));
}

class _SequenceKeyGenerator implements CategoryKeyGenerator {
  int _main = 0;
  int _sub = 0;

  @override
  String mainCategoryKey() => 'usr_main_${_main++}';

  @override
  String subCategoryKey() => 'usr_sub_${_sub++}';
}

class _MemoryCategoryRepository implements CategoryManagementRepository {
  final List<ManagedMainCategory> mains = [
    const ManagedMainCategory(
      id: 1,
      key: 'main_one',
      nameAr: 'رئيسية أولى',
      nameEn: 'Main One',
      sortOrder: 1,
      isActive: true,
    ),
    const ManagedMainCategory(
      id: 2,
      key: 'main_two',
      nameAr: 'رئيسية ثانية',
      nameEn: 'Main Two',
      sortOrder: 2,
      isActive: false,
    ),
  ];
  final List<ManagedSubCategory> subs = [
    const ManagedSubCategory(
      id: 10,
      mainCategoryId: 1,
      key: 'sub_one',
      nameAr: 'فرعية أولى',
      nameEn: 'Sub One',
      sortOrder: 1,
      isActive: true,
    ),
  ];

  bool rejectMovesAsUsed = false;

  @override
  Future<List<ManagedMainCategory>> getMainCategories() async =>
      List.unmodifiable(mains);

  @override
  Future<List<ManagedSubCategory>> getSubCategories({
    int? mainCategoryId,
  }) async {
    final values = mainCategoryId == null
        ? subs
        : subs.where((s) => s.mainCategoryId == mainCategoryId);
    return List.unmodifiable(values);
  }

  @override
  Future<int> insertMainCategory({
    required String key,
    required String nameAr,
    required String nameEn,
  }) async {
    final id = mains.length + 1;
    mains.add(
      ManagedMainCategory(
        id: id,
        key: key,
        nameAr: nameAr,
        nameEn: nameEn,
        sortOrder: mains.length + 1,
        isActive: true,
      ),
    );
    return id;
  }

  @override
  Future<int> insertSubCategory({
    required int mainCategoryId,
    required String key,
    required String nameAr,
    required String nameEn,
  }) async {
    final id = subs.length + 10;
    subs.add(
      ManagedSubCategory(
        id: id,
        mainCategoryId: mainCategoryId,
        key: key,
        nameAr: nameAr,
        nameEn: nameEn,
        sortOrder:
            subs.where((s) => s.mainCategoryId == mainCategoryId).length + 1,
        isActive: true,
      ),
    );
    return id;
  }

  @override
  Future<void> updateMainCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  }) async {
    final index = mains.indexWhere((m) => m.id == id);
    final current = mains[index];
    mains[index] = ManagedMainCategory(
      id: current.id,
      key: current.key,
      nameAr: nameAr,
      nameEn: nameEn,
      sortOrder: current.sortOrder,
      isActive: current.isActive,
    );
  }

  @override
  Future<void> updateSubCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  }) async {
    final index = subs.indexWhere((s) => s.id == id);
    final current = subs[index];
    subs[index] = ManagedSubCategory(
      id: current.id,
      mainCategoryId: current.mainCategoryId,
      key: current.key,
      nameAr: nameAr,
      nameEn: nameEn,
      sortOrder: current.sortOrder,
      isActive: current.isActive,
    );
  }

  @override
  Future<void> moveSubCategory({
    required int subCategoryId,
    required int newMainCategoryId,
  }) async {
    if (rejectMovesAsUsed) throw const SubCategoryInUseException();
    final index = subs.indexWhere((s) => s.id == subCategoryId);
    final current = subs[index];
    subs[index] = ManagedSubCategory(
      id: current.id,
      mainCategoryId: newMainCategoryId,
      key: current.key,
      nameAr: current.nameAr,
      nameEn: current.nameEn,
      sortOrder: current.sortOrder,
      isActive: current.isActive,
    );
  }

  @override
  Future<void> reorderMainCategory({required int idA, required int idB}) async {
    // Swap sort orders in the in-memory list for the test.
    final indexA = mains.indexWhere((m) => m.id == idA);
    final indexB = mains.indexWhere((m) => m.id == idB);
    if (indexA < 0 || indexB < 0) return;
    final sortA = mains[indexA].sortOrder;
    final sortB = mains[indexB].sortOrder;
    mains[indexA] = ManagedMainCategory(
      id: mains[indexA].id,
      key: mains[indexA].key,
      nameAr: mains[indexA].nameAr,
      nameEn: mains[indexA].nameEn,
      sortOrder: sortB,
      isActive: mains[indexA].isActive,
    );
    mains[indexB] = ManagedMainCategory(
      id: mains[indexB].id,
      key: mains[indexB].key,
      nameAr: mains[indexB].nameAr,
      nameEn: mains[indexB].nameEn,
      sortOrder: sortA,
      isActive: mains[indexB].isActive,
    );
  }

  @override
  Future<void> reorderSubCategory({required int idA, required int idB}) async {}

  @override
  Future<void> setMainCategoryActive(int id, {required bool isActive}) async {
    final index = mains.indexWhere((m) => m.id == id);
    final current = mains[index];
    mains[index] = ManagedMainCategory(
      id: current.id,
      key: current.key,
      nameAr: current.nameAr,
      nameEn: current.nameEn,
      sortOrder: current.sortOrder,
      isActive: isActive,
    );
  }

  @override
  Future<void> setSubCategoryActive(int id, {required bool isActive}) async {
    final index = subs.indexWhere((s) => s.id == id);
    final current = subs[index];
    subs[index] = ManagedSubCategory(
      id: current.id,
      mainCategoryId: current.mainCategoryId,
      key: current.key,
      nameAr: current.nameAr,
      nameEn: current.nameEn,
      sortOrder: current.sortOrder,
      isActive: isActive,
    );
  }

  @override
  Future<bool> isSubCategoryUsed(int subCategoryId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by this test');
}
