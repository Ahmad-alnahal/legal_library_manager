import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/features/documents/domain/validation/membership_validators.dart';
import 'package:legal_library_manager/features/reference/domain/entities/sub_category_ref.dart';

void main() {
  group('MembershipValidators', () {
    const sub = SubCategoryRef(
      id: 5,
      mainCategoryId: 2,
      key: 'civil_law',
      nameAr: 'مدني',
      nameEn: 'Civil',
      sortOrder: 1,
    );

    test('subCategoryBelongsToMain', () {
      expect(MembershipValidators.subCategoryBelongsToMain(sub, 2), isTrue);
      expect(MembershipValidators.subCategoryBelongsToMain(sub, 3), isFalse);
    });

    test('subCategoryIdBelongsToMain via mapping', () {
      const map = {5: 2, 6: 3};
      expect(
        MembershipValidators.subCategoryIdBelongsToMain(
          subCategoryId: 5,
          mainCategoryId: 2,
          mainBySubCategoryId: map,
        ),
        isTrue,
      );
      expect(
        MembershipValidators.subCategoryIdBelongsToMain(
          subCategoryId: 6,
          mainCategoryId: 2,
          mainBySubCategoryId: map,
        ),
        isFalse,
      );
    });

    test('preferredFileBelongsToGroup (null allowed)', () {
      expect(
        MembershipValidators.preferredFileBelongsToGroup(
          preferredFileId: null,
          groupFileIds: {1, 2},
        ),
        isTrue,
      );
      expect(
        MembershipValidators.preferredFileBelongsToGroup(
          preferredFileId: 2,
          groupFileIds: {1, 2},
        ),
        isTrue,
      );
      expect(
        MembershipValidators.preferredFileBelongsToGroup(
          preferredFileId: 9,
          groupFileIds: {1, 2},
        ),
        isFalse,
      );
    });

    test(
      'exportManagedFileIsValid requires membership and managed_copy role',
      () {
        expect(
          MembershipValidators.exportManagedFileIsValid(
            snapshotDocumentId: 1,
            fileDocumentId: 1,
            fileRoleKey: FileRoleKey.managedCopy,
          ),
          isTrue,
        );
        // Wrong document.
        expect(
          MembershipValidators.exportManagedFileIsValid(
            snapshotDocumentId: 1,
            fileDocumentId: 2,
            fileRoleKey: FileRoleKey.managedCopy,
          ),
          isFalse,
        );
        // Wrong role (a source file is not exportable as a managed copy).
        expect(
          MembershipValidators.exportManagedFileIsValid(
            snapshotDocumentId: 1,
            fileDocumentId: 1,
            fileRoleKey: FileRoleKey.sourceOriginal,
          ),
          isFalse,
        );
      },
    );
  });
}
