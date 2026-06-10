import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/categories/data/repositories/drift_category_management_repository.dart';
import 'package:legal_library_manager/features/categories/domain/repositories/category_management_repository.dart';
import 'package:legal_library_manager/features/categories/domain/services/category_name.dart';
import 'package:sqlite3/common.dart' show SqliteException;

void main() {
  group('DriftCategoryManagementRepository', () {
    late AppDatabase db;
    late DriftCategoryManagementRepository repository;

    const now = '2026-06-09T12:00:00.000Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      repository = DriftCategoryManagementRepository(db);
    });

    tearDown(() => db.close());

    test('adds and edits categories without changing ids or keys', () async {
      final mainId = await repository.insertMainCategory(
        key: 'usr_main_test',
        nameAr: 'فئة تجريبية',
        nameEn: 'Test Category',
      );
      final subId = await repository.insertSubCategory(
        mainCategoryId: mainId,
        key: 'usr_sub_test',
        nameAr: 'فئة فرعية تجريبية',
        nameEn: 'Test Subcategory',
      );

      await repository.updateMainCategory(
        id: mainId,
        nameAr: 'فئة معدلة',
        nameEn: 'Edited Category',
      );
      await repository.updateSubCategory(
        id: subId,
        nameAr: 'فئة فرعية معدلة',
        nameEn: 'Edited Subcategory',
      );

      final main = (await repository.getMainCategories()).firstWhere(
        (item) => item.id == mainId,
      );
      final sub = (await repository.getSubCategories()).firstWhere(
        (item) => item.id == subId,
      );
      expect(main.key, 'usr_main_test');
      expect(main.nameAr, 'فئة معدلة');
      expect(sub.key, 'usr_sub_test');
      expect(sub.mainCategoryId, mainId);
      expect(sub.nameAr, 'فئة فرعية معدلة');
    });

    test('rejects normalized duplicate names', () async {
      await repository.insertMainCategory(
        key: 'usr_main_one',
        nameAr: 'فئة جديدة',
        nameEn: 'New Category',
      );

      await expectLater(
        repository.insertMainCategory(
          key: 'usr_main_two',
          nameAr: '  فئة   جديدة ',
          nameEn: 'Different',
        ),
        throwsA(isA<DuplicateCategoryNameException>()),
      );
      await expectLater(
        repository.insertMainCategory(
          key: 'usr_main_three',
          nameAr: 'مختلفة',
          nameEn: ' new category ',
        ),
        throwsA(isA<DuplicateCategoryNameException>()),
      );
    });

    test('activation changes never remove referenced categories', () async {
      final main = (await repository.getMainCategories()).first;
      final sub = (await repository.getSubCategories(
        mainCategoryId: main.id,
      )).first;
      final documentId = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              primaryMainCategoryId: Value(main.id),
              primarySubCategoryId: Value(sub.id),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await repository.setMainCategoryActive(main.id, isActive: false);
      await repository.setSubCategoryActive(sub.id, isActive: false);

      final storedDocument = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(documentId))).getSingle();
      expect(storedDocument.primaryMainCategoryId, main.id);
      expect(storedDocument.primarySubCategoryId, sub.id);
      expect(
        (await repository.getMainCategories())
            .firstWhere((item) => item.id == main.id)
            .isActive,
        isFalse,
      );
      expect(
        (await repository.getSubCategories())
            .firstWhere((item) => item.id == sub.id)
            .isActive,
        isFalse,
      );
    });

    test('moves an unused subcategory to another main category', () async {
      final mains = await repository.getMainCategories();
      final source = mains[0];
      final target = mains[1];
      final subId = await repository.insertSubCategory(
        mainCategoryId: source.id,
        key: 'usr_sub_move',
        nameAr: 'فرعية للنقل',
        nameEn: 'Movable Subcategory',
      );

      await repository.moveSubCategory(
        subCategoryId: subId,
        newMainCategoryId: target.id,
      );

      final moved = (await repository.getSubCategories()).firstWhere(
        (item) => item.id == subId,
      );
      expect(moved.mainCategoryId, target.id);
      expect(moved.key, 'usr_sub_move');
    });

    test('rejects moving a subcategory referenced by a document', () async {
      final mains = await repository.getMainCategories();
      final source = mains[0];
      final target = mains[1];
      final sub = (await repository.getSubCategories(
        mainCategoryId: source.id,
      )).first;
      await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              primaryMainCategoryId: Value(source.id),
              primarySubCategoryId: Value(sub.id),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await expectLater(
        repository.moveSubCategory(
          subCategoryId: sub.id,
          newMainCategoryId: target.id,
        ),
        throwsA(isA<SubCategoryInUseException>()),
      );
      final unchanged = (await repository.getSubCategories()).firstWhere(
        (item) => item.id == sub.id,
      );
      expect(unchanged.mainCategoryId, source.id);
    });

    test(
      'rejects moving a subcategory referenced by a classification row',
      () async {
        final mains = await repository.getMainCategories();
        final source = mains[0];
        final target = mains[1];
        final sub = (await repository.getSubCategories(
          mainCategoryId: source.id,
        )).first;
        final documentId = await db
            .into(db.documents)
            .insert(DocumentsCompanion.insert(createdAt: now, updatedAt: now));
        await db
            .into(db.documentClassifications)
            .insert(
              DocumentClassificationsCompanion.insert(
                documentId: documentId,
                mainCategoryId: source.id,
                subCategoryId: Value(sub.id),
                classificationRoleKey: 'additional',
                createdAt: now,
              ),
            );

        await expectLater(
          repository.moveSubCategory(
            subCategoryId: sub.id,
            newMainCategoryId: target.id,
          ),
          throwsA(isA<SubCategoryInUseException>()),
        );
      },
    );

    // --- M6.4 normalized-name integrity ---

    Future<({String ar, String en})> mainNormalized(int id) async {
      final row = await (db.select(
        db.mainCategories,
      )..where((t) => t.id.equals(id))).getSingle();
      return (ar: row.normalizedNameAr, en: row.normalizedNameEn);
    }

    test('enforces main-category normalized Arabic uniqueness', () async {
      await expectLater(
        repository.insertMainCategory(
          key: 'usr_main_ar_dup',
          nameAr: '  القانون   العام ',
          nameEn: 'A Distinct English Name',
        ),
        throwsA(
          isA<DuplicateCategoryNameException>().having(
            (e) => e.field,
            'field',
            'nameAr',
          ),
        ),
      );
    });

    test('enforces main-category normalized English uniqueness', () async {
      await expectLater(
        repository.insertMainCategory(
          key: 'usr_main_en_dup',
          nameAr: 'اسم عربي مختلف تمامًا',
          nameEn: ' PUBLIC   law ',
        ),
        throwsA(
          isA<DuplicateCategoryNameException>().having(
            (e) => e.field,
            'field',
            'nameEn',
          ),
        ),
      );
    });

    test(
      'enforces subcategory normalized uniqueness within a parent',
      () async {
        final publicLaw = (await repository.getMainCategories()).firstWhere(
          (m) => m.key == 'public_law',
        );
        await expectLater(
          repository.insertSubCategory(
            mainCategoryId: publicLaw.id,
            key: 'usr_sub_dup',
            nameAr: '  القانون   الدستوري ',
            nameEn: 'A Distinct English Sub',
          ),
          throwsA(isA<DuplicateCategoryNameException>()),
        );
      },
    );

    test('allows the same subcategory name under different parents', () async {
      final mains = await repository.getMainCategories();
      final first = mains[0];
      final second = mains[1];

      final idA = await repository.insertSubCategory(
        mainCategoryId: first.id,
        key: 'usr_sub_shared_a',
        nameAr: 'اسم مشترك',
        nameEn: 'Shared Sub Name',
      );
      final idB = await repository.insertSubCategory(
        mainCategoryId: second.id,
        key: 'usr_sub_shared_b',
        nameAr: 'اسم مشترك',
        nameEn: 'Shared Sub Name',
      );

      expect(idA, isNot(idB));
      final subs = await repository.getSubCategories();
      expect(subs.where((s) => s.nameEn == 'Shared Sub Name').length, 2);
    });

    test('SQLite rejects a direct duplicate normalized insert', () async {
      await db
          .into(db.mainCategories)
          .insert(
            MainCategoriesCompanion.insert(
              key: 'usr_raw_one',
              nameAr: 'فئة خام',
              nameEn: 'Raw Category',
              normalizedNameAr: 'rawcat',
              normalizedNameEn: 'rawcat_en',
              sortOrder: 80,
              isActive: true,
            ),
          );

      await expectLater(
        db
            .into(db.mainCategories)
            .insert(
              MainCategoriesCompanion.insert(
                key: 'usr_raw_two',
                nameAr: 'فئة خام أخرى',
                nameEn: 'Another Raw',
                normalizedNameAr: 'rawcat', // same normalized Arabic value
                normalizedNameEn: 'different_en',
                sortOrder: 81,
                isActive: true,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('insert, edit, and move keep normalized values correct', () async {
      final id = await repository.insertMainCategory(
        key: 'usr_main_norm',
        nameAr: '  فئة   جديدة ',
        nameEn: '  Spaced   Category ',
      );
      final stored = await (db.select(
        db.mainCategories,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(stored.nameAr, 'فئة جديدة');
      expect(stored.nameEn, 'Spaced Category');
      var norm = await mainNormalized(id);
      expect(norm.ar, normalizedCategoryNameAr('فئة جديدة'));
      expect(norm.en, normalizedCategoryNameEn('Spaced Category'));

      await repository.updateMainCategory(
        id: id,
        nameAr: 'فئة محدثة',
        nameEn: 'Updated Category',
      );
      norm = await mainNormalized(id);
      expect(norm.ar, normalizedCategoryNameAr('فئة محدثة'));
      expect(norm.en, normalizedCategoryNameEn('Updated Category'));

      final target = (await repository.getMainCategories()).firstWhere(
        (m) => m.id != id && m.isActive,
      );
      final subId = await repository.insertSubCategory(
        mainCategoryId: id,
        key: 'usr_sub_norm',
        nameAr: 'فرعية متنقلة',
        nameEn: 'Movable Sub',
      );
      await repository.moveSubCategory(
        subCategoryId: subId,
        newMainCategoryId: target.id,
      );
      final movedRow = await (db.select(
        db.subCategories,
      )..where((t) => t.id.equals(subId))).getSingle();
      expect(movedRow.mainCategoryId, target.id);
      expect(
        movedRow.normalizedNameAr,
        normalizedCategoryNameAr('فرعية متنقلة'),
      );
      expect(
        movedRow.normalizedNameEn,
        normalizedCategoryNameEn('Movable Sub'),
      );
    });

    test(
      'translates a unique-constraint race into a safe duplicate error',
      () async {
        await db
            .into(db.mainCategories)
            .insert(
              MainCategoriesCompanion.insert(
                key: 'usr_poison',
                nameAr: 'اسم ظاهر',
                nameEn: 'Visible Name',
                normalizedNameAr: 'zzz_norm',
                normalizedNameEn: 'visible name',
                sortOrder: 95,
                isActive: true,
              ),
            );

        await expectLater(
          repository.insertMainCategory(
            key: 'usr_poison_clash',
            nameAr: 'zzz_norm',
            nameEn: 'A Unique English Name',
          ),
          throwsA(
            isA<DuplicateCategoryNameException>().having(
              (e) => e.field,
              'field',
              'nameAr',
            ),
          ),
        );
      },
    );

    // --- M6.5 automatic ordering ---

    test('new main categories are placed last automatically', () async {
      final idA = await repository.insertMainCategory(
        key: 'usr_order_a',
        nameAr: 'ترتيب أ',
        nameEn: 'Order A',
      );
      final idB = await repository.insertMainCategory(
        key: 'usr_order_b',
        nameAr: 'ترتيب ب',
        nameEn: 'Order B',
      );
      final idC = await repository.insertMainCategory(
        key: 'usr_order_c',
        nameAr: 'ترتيب ج',
        nameEn: 'Order C',
      );

      final mains = await repository.getMainCategories();
      final idxA = mains.indexWhere((m) => m.id == idA);
      final idxB = mains.indexWhere((m) => m.id == idB);
      final idxC = mains.indexWhere((m) => m.id == idC);
      expect(
        idxA < idxB,
        isTrue,
        reason: 'A should appear before B in getMainCategories()',
      );
      expect(
        idxB < idxC,
        isTrue,
        reason: 'B should appear before C in getMainCategories()',
      );
    });

    test('first subcategory under a new parent gets position 1', () async {
      final parentId = await repository.insertMainCategory(
        key: 'usr_empty_parent',
        nameAr: 'فئة رئيسية فارغة',
        nameEn: 'Empty Parent',
      );
      final subId = await repository.insertSubCategory(
        mainCategoryId: parentId,
        key: 'usr_first_sub_empty',
        nameAr: 'فرعية أولى للفارغة',
        nameEn: 'First Sub',
      );

      final subs = await repository.getSubCategories(mainCategoryId: parentId);
      expect(subs.single.id, subId);
      expect(subs.single.sortOrder, 1);
    });

    test('new subcategories are placed last under their parent', () async {
      final mains = await repository.getMainCategories();
      final parentId = mains.first.id;

      final idA = await repository.insertSubCategory(
        mainCategoryId: parentId,
        key: 'usr_sub_order_a',
        nameAr: 'فرعية تسلسل أ',
        nameEn: 'Sub Order A',
      );
      final idB = await repository.insertSubCategory(
        mainCategoryId: parentId,
        key: 'usr_sub_order_b',
        nameAr: 'فرعية تسلسل ب',
        nameEn: 'Sub Order B',
      );

      final subs = await repository.getSubCategories(mainCategoryId: parentId);
      final idxA = subs.indexWhere((s) => s.id == idA);
      final idxB = subs.indexWhere((s) => s.id == idB);
      expect(
        idxA < idxB,
        isTrue,
        reason: 'A should appear before B in getSubCategories()',
      );
    });

    test('editing a main category preserves its sort order', () async {
      final idA = await repository.insertMainCategory(
        key: 'usr_edit_sort_a',
        nameAr: 'أولى تحرير',
        nameEn: 'Edit Sort A',
      );
      final idB = await repository.insertMainCategory(
        key: 'usr_edit_sort_b',
        nameAr: 'ثانية تحرير',
        nameEn: 'Edit Sort B',
      );
      final sortBefore = (await repository.getMainCategories())
          .firstWhere((m) => m.id == idA)
          .sortOrder;

      await repository.updateMainCategory(
        id: idA,
        nameAr: 'أولى تحرير معدلة',
        nameEn: 'Edit Sort A Renamed',
      );

      final sortAfter = (await repository.getMainCategories())
          .firstWhere((m) => m.id == idA)
          .sortOrder;
      expect(
        sortAfter,
        sortBefore,
        reason: 'sort order must not change on edit',
      );

      // Relative order of the two items is also unchanged.
      final mains = await repository.getMainCategories();
      final idxA = mains.indexWhere((m) => m.id == idA);
      final idxB = mains.indexWhere((m) => m.id == idB);
      expect(idxA < idxB, isTrue);
    });

    test('reorder main categories swaps two items and resequences', () async {
      final idA = await repository.insertMainCategory(
        key: 'usr_reorder_a',
        nameAr: 'تسلسل أ',
        nameEn: 'Reorder A',
      );
      final idB = await repository.insertMainCategory(
        key: 'usr_reorder_b',
        nameAr: 'تسلسل ب',
        nameEn: 'Reorder B',
      );
      final idC = await repository.insertMainCategory(
        key: 'usr_reorder_c',
        nameAr: 'تسلسل ج',
        nameEn: 'Reorder C',
      );

      // Confirm initial order: A before B before C.
      var mains = await repository.getMainCategories();
      expect(
        mains.indexWhere((m) => m.id == idA),
        lessThan(mains.indexWhere((m) => m.id == idB)),
      );

      // Swap B and A (move B up).
      await repository.reorderMainCategory(idA: idB, idB: idA);

      mains = await repository.getMainCategories();
      final idxA = mains.indexWhere((m) => m.id == idA);
      final idxB = mains.indexWhere((m) => m.id == idB);
      final idxC = mains.indexWhere((m) => m.id == idC);
      expect(idxB < idxA, isTrue, reason: 'B should now precede A');
      expect(idxA < idxC, isTrue, reason: 'A should still precede C');

      // IDs and keys are immutable.
      expect(mains.firstWhere((m) => m.id == idA).key, 'usr_reorder_a');
      expect(mains.firstWhere((m) => m.id == idB).key, 'usr_reorder_b');

      // Sort orders are sequential (no gaps).
      final orders = mains.map((m) => m.sortOrder).toList();
      for (var i = 0; i < orders.length; i++) {
        expect(
          orders[i],
          i + 1,
          reason: 'sort_order at index $i must equal ${i + 1}',
        );
      }
    });

    test('reorder subcategories swaps within sibling scope', () async {
      final parentId = (await repository.getMainCategories()).first.id;

      final idA = await repository.insertSubCategory(
        mainCategoryId: parentId,
        key: 'usr_sub_reo_a',
        nameAr: 'فرعية تسلسل أ',
        nameEn: 'Sub Reorder A',
      );
      final idB = await repository.insertSubCategory(
        mainCategoryId: parentId,
        key: 'usr_sub_reo_b',
        nameAr: 'فرعية تسلسل ب',
        nameEn: 'Sub Reorder B',
      );

      // Initial: A before B.
      var subs = await repository.getSubCategories(mainCategoryId: parentId);
      expect(
        subs.indexWhere((s) => s.id == idA),
        lessThan(subs.indexWhere((s) => s.id == idB)),
      );

      // Swap B and A.
      await repository.reorderSubCategory(idA: idB, idB: idA);

      subs = await repository.getSubCategories(mainCategoryId: parentId);
      final idxA = subs.indexWhere((s) => s.id == idA);
      final idxB = subs.indexWhere((s) => s.id == idB);
      expect(idxB < idxA, isTrue, reason: 'B should now precede A');

      // Sort orders sequential.
      final orders = subs.map((s) => s.sortOrder).toList();
      for (var i = 0; i < orders.length; i++) {
        expect(orders[i], i + 1);
      }
    });

    test(
      'reordering with inactive categories hidden remains globally consistent',
      () async {
        final idActive1 = await repository.insertMainCategory(
          key: 'usr_vis_1',
          nameAr: 'نشطة أولى',
          nameEn: 'Visible One',
        );
        final idInactive = await repository.insertMainCategory(
          key: 'usr_inact',
          nameAr: 'معطلة',
          nameEn: 'Inactive One',
        );
        await repository.setMainCategoryActive(idInactive, isActive: false);
        final idActive2 = await repository.insertMainCategory(
          key: 'usr_vis_2',
          nameAr: 'نشطة ثانية',
          nameEn: 'Visible Two',
        );

        // Visible list: [Active1, Active2]; global: [Active1, Inactive, Active2].
        // Simulate "move Active2 up" in the displayed list (swap with Active1).
        await repository.reorderMainCategory(idA: idActive2, idB: idActive1);

        final all = await repository.getMainCategories();
        final posActive1 = all.indexWhere((m) => m.id == idActive1);
        final posActive2 = all.indexWhere((m) => m.id == idActive2);
        // Active2 now comes before Active1 globally.
        expect(
          posActive2 < posActive1,
          isTrue,
          reason: 'Active2 should precede Active1 after reorder',
        );

        // All sort orders remain sequential.
        final orders = all.map((m) => m.sortOrder).toList();
        for (var i = 0; i < orders.length; i++) {
          expect(orders[i], i + 1);
        }
      },
    );

    test(
      'reordering main categories does not affect subcategory positions',
      () async {
        final idMainA = await repository.insertMainCategory(
          key: 'usr_cross_ma',
          nameAr: 'رئيسية عبر أ',
          nameEn: 'Cross Main A',
        );
        final idMainB = await repository.insertMainCategory(
          key: 'usr_cross_mb',
          nameAr: 'رئيسية عبر ب',
          nameEn: 'Cross Main B',
        );
        final subId1 = await repository.insertSubCategory(
          mainCategoryId: idMainA,
          key: 'usr_cross_s1',
          nameAr: 'فرعية عبر ١',
          nameEn: 'Cross Sub 1',
        );
        final subId2 = await repository.insertSubCategory(
          mainCategoryId: idMainA,
          key: 'usr_cross_s2',
          nameAr: 'فرعية عبر ٢',
          nameEn: 'Cross Sub 2',
        );

        final sortBefore1 = (await repository.getSubCategories(
          mainCategoryId: idMainA,
        )).firstWhere((s) => s.id == subId1).sortOrder;
        final sortBefore2 = (await repository.getSubCategories(
          mainCategoryId: idMainA,
        )).firstWhere((s) => s.id == subId2).sortOrder;

        // Swap the two main categories.
        await repository.reorderMainCategory(idA: idMainB, idB: idMainA);

        final sortAfter1 = (await repository.getSubCategories(
          mainCategoryId: idMainA,
        )).firstWhere((s) => s.id == subId1).sortOrder;
        final sortAfter2 = (await repository.getSubCategories(
          mainCategoryId: idMainA,
        )).firstWhere((s) => s.id == subId2).sortOrder;

        expect(
          sortAfter1,
          sortBefore1,
          reason: 'subcategory sort_order must be unaffected by main reorder',
        );
        expect(sortAfter2, sortBefore2);
      },
    );

    test(
      'reordering subcategories in one parent never affects another parent',
      () async {
        final mains = await repository.getMainCategories();
        final parentA = mains[0];
        final parentB = mains[1];

        final subA1 = await repository.insertSubCategory(
          mainCategoryId: parentA.id,
          key: 'usr_iso_a1',
          nameAr: 'فرعية أ ١',
          nameEn: 'Iso A1',
        );
        final subA2 = await repository.insertSubCategory(
          mainCategoryId: parentA.id,
          key: 'usr_iso_a2',
          nameAr: 'فرعية أ ٢',
          nameEn: 'Iso A2',
        );
        final subB1 = await repository.insertSubCategory(
          mainCategoryId: parentB.id,
          key: 'usr_iso_b1',
          nameAr: 'فرعية ب ١',
          nameEn: 'Iso B1',
        );

        final sortB1Before = (await repository.getSubCategories(
          mainCategoryId: parentB.id,
        )).firstWhere((s) => s.id == subB1).sortOrder;

        // Reorder parent A's subs.
        await repository.reorderSubCategory(idA: subA2, idB: subA1);

        final sortB1After = (await repository.getSubCategories(
          mainCategoryId: parentB.id,
        )).firstWhere((s) => s.id == subB1).sortOrder;

        expect(
          sortB1After,
          sortB1Before,
          reason:
              'parent B sub order must not change when parent A is reordered',
        );
      },
    );

    test(
      'move places subcategory last in target and resequences both collections',
      () async {
        // Use fresh parents with no pre-seeded subs so position assertions
        // are not affected by seeded reference data.
        final sourceId = await repository.insertMainCategory(
          key: 'usr_mv_source_parent',
          nameAr: 'مصدر الفئة الرئيسية',
          nameEn: 'Move Source Parent',
        );
        final targetId = await repository.insertMainCategory(
          key: 'usr_mv_target_parent',
          nameAr: 'هدف الفئة الرئيسية',
          nameEn: 'Move Target Parent',
        );

        // Add 3 subs to source.
        final srcId1 = await repository.insertSubCategory(
          mainCategoryId: sourceId,
          key: 'usr_mv_src1',
          nameAr: 'مصدر فرعية ١',
          nameEn: 'Mv Src 1',
        );
        final srcId2 = await repository.insertSubCategory(
          mainCategoryId: sourceId,
          key: 'usr_mv_src2',
          nameAr: 'مصدر فرعية ٢',
          nameEn: 'Mv Src 2',
        );
        final srcId3 = await repository.insertSubCategory(
          mainCategoryId: sourceId,
          key: 'usr_mv_src3',
          nameAr: 'مصدر فرعية ٣',
          nameEn: 'Mv Src 3',
        );
        // Add 1 sub to target.
        final tgtId1 = await repository.insertSubCategory(
          mainCategoryId: targetId,
          key: 'usr_mv_tgt1',
          nameAr: 'هدف فرعية ١',
          nameEn: 'Mv Tgt 1',
        );

        // Move the middle source sub to target.
        await repository.moveSubCategory(
          subCategoryId: srcId2,
          newMainCategoryId: targetId,
        );

        // Source now has srcId1, srcId3 resequenced as 1, 2.
        final srcSubs = await repository.getSubCategories(
          mainCategoryId: sourceId,
        );
        final srcUser = srcSubs
            .where((s) => s.id == srcId1 || s.id == srcId3)
            .toList();
        expect(srcUser.length, 2);
        expect(srcUser[0].sortOrder, 1);
        expect(srcUser[1].sortOrder, 2);

        // Target has tgtId1 then srcId2 (placed last).
        final tgtSubs = await repository.getSubCategories(
          mainCategoryId: targetId,
        );
        final tgt1 = tgtSubs.firstWhere((s) => s.id == tgtId1);
        final moved = tgtSubs.firstWhere((s) => s.id == srcId2);
        expect(
          tgt1.sortOrder,
          lessThan(moved.sortOrder),
          reason: 'original target sub must precede the moved sub',
        );

        // Target sort orders are sequential.
        final tgtOrders = tgtSubs.map((s) => s.sortOrder).toList();
        for (var i = 0; i < tgtOrders.length; i++) {
          expect(tgtOrders[i], i + 1);
        }

        // IDs and keys are unchanged.
        expect(moved.key, 'usr_mv_src2');
        expect(moved.id, srcId2);
        // Source sub3 stays in source.
        expect(srcSubs.any((s) => s.id == srcId3), isTrue);
      },
    );
  });
}
