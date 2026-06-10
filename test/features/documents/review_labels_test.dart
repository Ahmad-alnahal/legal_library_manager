import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/categories/data/repositories/drift_category_management_repository.dart';
import 'package:legal_library_manager/features/documents/presentation/widgets/review_labels.dart';
import 'package:legal_library_manager/features/reference/data/repositories/drift_reference_repository.dart';

void main() {
  test(
    'review references reload category changes and preserve inactive names',
    () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      await ReferenceSeeder(db).seedAll();
      final references = DriftReferenceRepository(db);
      final categories = DriftCategoryManagementRepository(db);
      final main = (await categories.getMainCategories()).first;

      await categories.updateMainCategory(
        id: main.id,
        nameAr: 'اسم محدث',
        nameEn: 'Updated Name',
      );
      var loaded = await ReviewReferences.load(references, categories);
      expect(loaded.mainCategoryName(main.id), 'اسم محدث');
      expect(
        loaded.mainCategories.firstWhere((item) => item.id == main.id).nameAr,
        'اسم محدث',
      );

      await categories.setMainCategoryActive(main.id, isActive: false);
      loaded = await ReviewReferences.load(references, categories);
      expect(loaded.mainCategories.any((item) => item.id == main.id), isFalse);
      expect(loaded.mainCategoryName(main.id), 'اسم محدث');
      expect(
        loaded
            .mainCategoryOptions(main.id)
            .firstWhere((option) => option.id == main.id)
            .label,
        contains('اسم محدث'),
      );
    },
  );
}
