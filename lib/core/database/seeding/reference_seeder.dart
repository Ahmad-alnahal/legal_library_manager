import 'package:drift/drift.dart';

import '../../constants/domain_keys.dart';
import '../../validation/category_name.dart';
import '../app_database.dart';
import 'country_seed_data.dart';

/// A single bilingual reference entry: stable English key plus display names.
typedef _Ref = ({String key, String nameAr, String nameEn});

/// Seeds the finalized bilingual reference data.
///
/// Lives in the data/database layer (never presentation). Seeding is:
/// - **idempotent**: re-running it never duplicates rows;
/// - **transactional**: all reference sets are written in one transaction;
/// - **safe to re-run**: existing keys are updated in place if their display
///   names / sort order change.
///
/// Only keys explicitly finalized in the specifications are seeded here.
/// App startup invokes [seedAll]; tests and maintenance tools may also call it
/// explicitly. Repeated calls are safe because seeding is idempotent.
class ReferenceSeeder {
  ReferenceSeeder(this._db);

  final AppDatabase _db;

  Future<void> seedAll() {
    return _db.transaction(() async {
      await _seedDocumentTypes();
      await _seedMainCategories();
      await _seedSubCategories();
      await _seedLanguages();
      await _seedCountries();
      await _seedWorkflowStatuses();
      await _seedFileRoles();
      await _seedFileHealthStatuses();
      await _seedTrustLevels();
      await _seedUsageRights();
      await _seedMetadataQualities();
    });
  }

  // --- Tables with an integer id + unique `key` (upsert on the key column). ---

  Future<void> _seedDocumentTypes() async {
    const List<_Ref> data = [
      (key: 'book', nameAr: 'كتاب', nameEn: 'Book'),
      (key: 'thesis', nameAr: 'رسالة ماجستير أو دكتوراه', nameEn: 'Thesis'),
      (key: 'research_paper', nameAr: 'بحث علمي', nameEn: 'Research Paper'),
      (key: 'legislation', nameAr: 'تشريع', nameEn: 'Legislation'),
      (
        key: 'court_precedent',
        nameAr: 'سابقة قضائية',
        nameEn: 'Court Precedent',
      ),
      (
        key: 'institutional_report',
        nameAr: 'تقرير صادر عن مؤسسة قانونية',
        nameEn: 'Institutional Report',
      ),
      (key: 'other', nameAr: 'أخرى', nameEn: 'Other'),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      final int order = i + 1;
      await _db
          .into(_db.documentTypes)
          .insert(
            DocumentTypesCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: order,
              isActive: true,
            ),
            onConflict: DoUpdate(
              (_) => DocumentTypesCompanion(
                nameAr: Value(r.nameAr),
                nameEn: Value(r.nameEn),
                sortOrder: Value(order),
                isActive: const Value(true),
              ),
              target: [_db.documentTypes.key],
            ),
          );
    }
  }

  Future<void> _seedMainCategories() async {
    const List<_Ref> data = [
      (key: 'public_law', nameAr: 'القانون العام', nameEn: 'Public Law'),
      (key: 'private_law', nameAr: 'القانون الخاص', nameEn: 'Private Law'),
      (
        key: 'international_law',
        nameAr: 'القانون الدولي',
        nameEn: 'International Law',
      ),
      (
        key: 'islamic_jurisprudence',
        nameAr: 'الفقه الإسلامي',
        nameEn: 'Islamic Jurisprudence',
      ),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      final int order = i + 1;
      final String normalizedAr = normalizedCategoryNameAr(r.nameAr);
      final String normalizedEn = normalizedCategoryNameEn(r.nameEn);
      await _db
          .into(_db.mainCategories)
          .insert(
            MainCategoriesCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              normalizedNameAr: normalizedAr,
              normalizedNameEn: normalizedEn,
              sortOrder: order,
              isActive: true,
            ),
            onConflict: DoUpdate(
              (_) => MainCategoriesCompanion(
                nameAr: Value(r.nameAr),
                nameEn: Value(r.nameEn),
                normalizedNameAr: Value(normalizedAr),
                normalizedNameEn: Value(normalizedEn),
                sortOrder: Value(order),
                isActive: const Value(true),
              ),
              target: [_db.mainCategories.key],
            ),
          );
    }
  }

  /// Seeds the finalized lean set of 17 legal subcategories.
  ///
  /// Parent main-category IDs are resolved by their stable English key (never
  /// hardcoded numeric IDs). `sort_order` restarts at 1 under each main
  /// category. Upserts on the unique subcategory key restore the canonical
  /// parent, names, order, and active state.
  Future<void> _seedSubCategories() async {
    // Grouped by parent key, in canonical per-parent order.
    const List<({String parentKey, String key, String nameAr, String nameEn})>
    data = [
      // Public Law.
      (
        parentKey: 'public_law',
        key: 'constitutional_law',
        nameAr: 'القانون الدستوري',
        nameEn: 'Constitutional Law',
      ),
      (
        parentKey: 'public_law',
        key: 'administrative_law',
        nameAr: 'القانون الإداري',
        nameEn: 'Administrative Law',
      ),
      (
        parentKey: 'public_law',
        key: 'criminal_law',
        nameAr: 'القانون الجنائي',
        nameEn: 'Criminal Law',
      ),
      (
        parentKey: 'public_law',
        key: 'human_rights',
        nameAr: 'حقوق الإنسان',
        nameEn: 'Human Rights',
      ),
      // Private Law.
      (
        parentKey: 'private_law',
        key: 'civil_law',
        nameAr: 'القانون المدني',
        nameEn: 'Civil Law',
      ),
      (
        parentKey: 'private_law',
        key: 'commercial_law',
        nameAr: 'القانون التجاري',
        nameEn: 'Commercial Law',
      ),
      (
        parentKey: 'private_law',
        key: 'corporate_law',
        nameAr: 'قانون الشركات',
        nameEn: 'Corporate Law',
      ),
      (
        parentKey: 'private_law',
        key: 'insurance_law',
        nameAr: 'قانون التأمين',
        nameEn: 'Insurance Law',
      ),
      // International Law.
      (
        parentKey: 'international_law',
        key: 'public_international_law',
        nameAr: 'القانون الدولي العام',
        nameEn: 'Public International Law',
      ),
      (
        parentKey: 'international_law',
        key: 'international_humanitarian_law',
        nameAr: 'القانون الدولي الإنساني',
        nameEn: 'International Humanitarian Law',
      ),
      (
        parentKey: 'international_law',
        key: 'private_international_law',
        nameAr: 'القانون الدولي الخاص',
        nameEn: 'Private International Law',
      ),
      (
        parentKey: 'international_law',
        key: 'international_criminal_law',
        nameAr: 'القانون الدولي الجنائي',
        nameEn: 'International Criminal Law',
      ),
      (
        parentKey: 'international_law',
        key: 'international_human_rights_law',
        nameAr: 'القانون الدولي لحقوق الإنسان',
        nameEn: 'International Human Rights Law',
      ),
      (
        parentKey: 'international_law',
        key: 'diplomatic_law',
        nameAr: 'القانون الدبلوماسي',
        nameEn: 'Diplomatic Law',
      ),
      // Islamic Jurisprudence.
      (
        parentKey: 'islamic_jurisprudence',
        key: 'principles_of_islamic_jurisprudence',
        nameAr: 'أصول الفقه',
        nameEn: 'Principles of Islamic Jurisprudence',
      ),
      (
        parentKey: 'islamic_jurisprudence',
        key: 'islamic_criminal_jurisprudence',
        nameAr: 'الفقه الجنائي',
        nameEn: 'Islamic Criminal Jurisprudence',
      ),
      (
        parentKey: 'islamic_jurisprudence',
        key: 'islamic_civil_and_transactions_jurisprudence',
        nameAr: 'الفقه المدني والمعاملات',
        nameEn: 'Islamic Civil and Transactions Jurisprudence',
      ),
    ];

    // Resolve parent IDs once by stable key.
    final Map<String, int> parentIdByKey = {
      for (final MainCategory c in await _db.select(_db.mainCategories).get())
        c.key: c.id,
    };

    // Per-parent running order, restarting at 1 under each main category.
    final Map<String, int> orderByParent = <String, int>{};
    for (final r in data) {
      final int? parentId = parentIdByKey[r.parentKey];
      if (parentId == null) {
        throw StateError(
          'Main category "${r.parentKey}" must be seeded before its '
          'subcategories.',
        );
      }
      final int order = (orderByParent[r.parentKey] ?? 0) + 1;
      orderByParent[r.parentKey] = order;

      final String normalizedAr = normalizedCategoryNameAr(r.nameAr);
      final String normalizedEn = normalizedCategoryNameEn(r.nameEn);
      await _db
          .into(_db.subCategories)
          .insert(
            SubCategoriesCompanion.insert(
              mainCategoryId: parentId,
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              normalizedNameAr: normalizedAr,
              normalizedNameEn: normalizedEn,
              sortOrder: order,
              isActive: true,
            ),
            onConflict: DoUpdate(
              (_) => SubCategoriesCompanion(
                mainCategoryId: Value(parentId),
                nameAr: Value(r.nameAr),
                nameEn: Value(r.nameEn),
                normalizedNameAr: Value(normalizedAr),
                normalizedNameEn: Value(normalizedEn),
                sortOrder: Value(order),
                isActive: const Value(true),
              ),
              target: [_db.subCategories.key],
            ),
          );
    }
  }

  // --- Key-PK reference tables (upsert on the primary key). ---

  /// Seeds the initially supported document languages.
  Future<void> _seedLanguages() async {
    const List<_Ref> data = [
      (key: 'ar', nameAr: 'العربية', nameEn: 'Arabic'),
      (key: 'en', nameAr: 'الإنجليزية', nameEn: 'English'),
      (key: 'other', nameAr: 'أخرى', nameEn: 'Other'),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      await _db
          .into(_db.languages)
          .insertOnConflictUpdate(
            LanguagesCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }

  /// Seeds the complete offline ISO 3166-1 alpha-2 country dataset.
  ///
  /// Ordering is deterministic: the State of Palestine is pinned first, then
  /// the remaining entries follow by English display name (see
  /// [orderedCountrySeedData]). Upserts on the primary key restore the
  /// canonical names, order, and active state without creating duplicates.
  Future<void> _seedCountries() async {
    final List<CountrySeed> ordered = orderedCountrySeedData();
    for (int i = 0; i < ordered.length; i++) {
      final CountrySeed c = ordered[i];
      await _db
          .into(_db.countries)
          .insertOnConflictUpdate(
            CountriesCompanion.insert(
              key: c.key,
              nameAr: c.nameAr,
              nameEn: c.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }

  Future<void> _seedWorkflowStatuses() async {
    const List<_Ref> data = [
      (key: WorkflowStatusKey.imported, nameAr: 'مستورد', nameEn: 'Imported'),
      (
        key: WorkflowStatusKey.needsReview,
        nameAr: 'يحتاج مراجعة',
        nameEn: 'Needs Review',
      ),
      (
        key: WorkflowStatusKey.inProgress,
        nameAr: 'قيد التصنيف',
        nameEn: 'In Progress',
      ),
      (
        key: WorkflowStatusKey.classified,
        nameAr: 'مصنف',
        nameEn: 'Classified',
      ),
      (
        key: WorkflowStatusKey.copiedToLibrary,
        nameAr: 'نُسخ إلى المكتبة',
        nameEn: 'Copied to Library',
      ),
      (
        key: WorkflowStatusKey.readyForExport,
        nameAr: 'جاهز للتصدير',
        nameEn: 'Ready for Export',
      ),
      (key: WorkflowStatusKey.archived, nameAr: 'مؤرشف', nameEn: 'Archived'),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      await _db
          .into(_db.workflowStatuses)
          .insertOnConflictUpdate(
            WorkflowStatusesCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }

  Future<void> _seedFileRoles() async {
    const List<_Ref> data = [
      (
        key: FileRoleKey.sourceOriginal,
        nameAr: 'ملف أصلي',
        nameEn: 'Source Original',
      ),
      (
        key: FileRoleKey.managedCopy,
        nameAr: 'نسخة مُدارة',
        nameEn: 'Managed Copy',
      ),
      (
        key: FileRoleKey.convertedPdf,
        nameAr: 'PDF محوّل',
        nameEn: 'Converted PDF',
      ),
      (
        key: FileRoleKey.exportCopy,
        nameAr: 'نسخة تصدير',
        nameEn: 'Export Copy',
      ),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      await _db
          .into(_db.fileRoles)
          .insertOnConflictUpdate(
            FileRolesCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }

  Future<void> _seedFileHealthStatuses() async {
    const List<_Ref> data = [
      (key: FileHealthKey.unknown, nameAr: 'غير معروف', nameEn: 'Unknown'),
      (key: FileHealthKey.healthy, nameAr: 'سليم', nameEn: 'Healthy'),
      (key: FileHealthKey.corrupted, nameAr: 'تالف', nameEn: 'Corrupted'),
      (
        key: FileHealthKey.unreadable,
        nameAr: 'غير قابل للقراءة',
        nameEn: 'Unreadable',
      ),
      (key: FileHealthKey.missing, nameAr: 'مفقود', nameEn: 'Missing'),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      await _db
          .into(_db.fileHealthStatuses)
          .insertOnConflictUpdate(
            FileHealthStatusesCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }

  Future<void> _seedTrustLevels() async {
    const List<_Ref> data = [
      (key: TrustLevelKey.trusted, nameAr: 'موثوق', nameEn: 'Trusted'),
      (key: TrustLevelKey.medium, nameAr: 'متوسط', nameEn: 'Medium'),
      (
        key: TrustLevelKey.unverified,
        nameAr: 'غير موثق',
        nameEn: 'Unverified',
      ),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      await _db
          .into(_db.trustLevels)
          .insertOnConflictUpdate(
            TrustLevelsCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }

  Future<void> _seedUsageRights() async {
    const List<_Ref> data = [
      (key: UsageRightsKey.unknown, nameAr: 'غير معروف', nameEn: 'Unknown'),
      (
        key: UsageRightsKey.personalUseOnly,
        nameAr: 'للاستخدام الشخصي فقط',
        nameEn: 'Personal Use Only',
      ),
      (
        key: UsageRightsKey.publishable,
        nameAr: 'قابل للنشر',
        nameEn: 'Publishable',
      ),
      (
        key: UsageRightsKey.openAccess,
        nameAr: 'وصول مفتوح',
        nameEn: 'Open Access',
      ),
      (
        key: UsageRightsKey.permissionRequired,
        nameAr: 'يحتاج إذن',
        nameEn: 'Permission Required',
      ),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      await _db
          .into(_db.usageRights)
          .insertOnConflictUpdate(
            UsageRightsCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }

  Future<void> _seedMetadataQualities() async {
    const List<_Ref> data = [
      (key: MetadataQualityKey.low, nameAr: 'منخفضة', nameEn: 'Low'),
      (key: MetadataQualityKey.medium, nameAr: 'متوسطة', nameEn: 'Medium'),
      (key: MetadataQualityKey.high, nameAr: 'عالية', nameEn: 'High'),
      (key: MetadataQualityKey.verified, nameAr: 'موثقة', nameEn: 'Verified'),
    ];
    for (int i = 0; i < data.length; i++) {
      final _Ref r = data[i];
      await _db
          .into(_db.metadataQualities)
          .insertOnConflictUpdate(
            MetadataQualitiesCompanion.insert(
              key: r.key,
              nameAr: r.nameAr,
              nameEn: r.nameEn,
              sortOrder: i + 1,
              isActive: true,
            ),
          );
    }
  }
}
