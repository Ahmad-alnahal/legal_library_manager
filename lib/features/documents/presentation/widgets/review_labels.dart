// lib/features/documents/presentation/widgets/review_labels.dart

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/validation/validation_error.dart';
import '../../../categories/domain/repositories/category_management_repository.dart';
import '../../../reference/domain/entities/document_type_ref.dart';
import '../../../reference/domain/entities/main_category_ref.dart';
import '../../../reference/domain/entities/reference_item.dart';
import '../../../reference/domain/entities/sub_category_ref.dart';
import '../../../reference/domain/repositories/reference_repository.dart';

/// A single selectable category option in the review form.
typedef CategoryOption = ({int id, String label});

/// All reference lists the review form needs, loaded once per workspace.
///
/// The active lists ([mainCategories]/[subCategories]) drive the selectable
/// options for *new* classifications, so deactivated categories never appear as
/// choices. The full name maps ([_allMainNames]/[_allSubNames]) additionally let
/// the form display and preserve a category a document already references even
/// after it has been deactivated.
class ReviewReferences {
  const ReviewReferences({
    required this.documentTypes,
    required this.mainCategories,
    required this.subCategories,
    required this.languages,
    required this.countries,
    required this.trustLevels,
    required this.usageRights,
    required this.metadataQualities,
    required this.workflowStatuses,
    required this._allMainNames,
    required this._allSubNames,
  });

  final List<DocumentTypeRef> documentTypes;
  final List<MainCategoryRef> mainCategories;
  final List<SubCategoryRef> subCategories;
  final List<ReferenceItem> languages;
  final List<ReferenceItem> countries;
  final List<ReferenceItem> trustLevels;
  final List<ReferenceItem> usageRights;
  final List<ReferenceItem> metadataQualities;
  final List<ReferenceItem> workflowStatuses;

  /// Arabic names for every main/sub category, active or not, for display.
  final Map<int, String> _allMainNames;
  final Map<int, String> _allSubNames;

  /// Subcategories belonging to [mainCategoryId], in order (active only).
  List<SubCategoryRef> subCategoriesFor(int? mainCategoryId) {
    if (mainCategoryId == null) return const [];
    return subCategories
        .where((s) => s.mainCategoryId == mainCategoryId)
        .toList(growable: false);
  }

  /// Main-category options: every active main category, plus [includeId] if it
  /// is currently referenced but inactive (so it stays visible and saveable).
  List<CategoryOption> mainCategoryOptions(int? includeId) {
    final options = <CategoryOption>[
      for (final m in mainCategories) (id: m.id, label: m.nameAr),
    ];
    if (includeId != null && !mainCategories.any((m) => m.id == includeId)) {
      final name = _allMainNames[includeId];
      if (name != null) {
        options.add((id: includeId, label: '$name (غير مفعّلة)'));
      }
    }
    return options;
  }

  /// Subcategory options under [mainCategoryId]: every active subcategory, plus
  /// [includeId] if it is currently referenced but inactive.
  List<CategoryOption> subCategoryOptions(int? mainCategoryId, int? includeId) {
    final options = <CategoryOption>[
      for (final s in subCategoriesFor(mainCategoryId))
        (id: s.id, label: s.nameAr),
    ];
    if (includeId != null && !options.any((o) => o.id == includeId)) {
      final name = _allSubNames[includeId];
      if (name != null) {
        options.add((id: includeId, label: '$name (غير مفعّلة)'));
      }
    }
    return options;
  }

  /// The document-type id for the 'legislation' type, or `null` if not found.
  int? get legislationDocumentTypeId {
    for (final t in documentTypes) {
      if (t.key == 'legislation') return t.id;
    }
    return null;
  }

  /// The stable document-type key for a type id, or `null`.
  String? typeKeyFor(int? documentTypeId) {
    if (documentTypeId == null) return null;
    for (final t in documentTypes) {
      if (t.id == documentTypeId) return t.key;
    }
    return null;
  }

  String mainCategoryName(int id) =>
      _allMainNames[id] ?? _activeMainName(id) ?? '#$id';

  String subCategoryName(int id) =>
      _allSubNames[id] ?? _activeSubName(id) ?? '#$id';

  String? _activeMainName(int id) {
    for (final m in mainCategories) {
      if (m.id == id) return m.nameAr;
    }
    return null;
  }

  String? _activeSubName(int id) {
    for (final s in subCategories) {
      if (s.id == id) return s.nameAr;
    }
    return null;
  }

  static Future<ReviewReferences> load(
    ReferenceRepository repo,
    CategoryManagementRepository categories,
  ) async {
    final (
      documentTypes,
      mainCategories,
      subCategories,
      languages,
      countries,
      trustLevels,
      usageRights,
      metadataQualities,
      workflowStatuses,
    ) = await (
      repo.getDocumentTypes(),
      repo.getMainCategories(),
      repo.getSubCategories(),
      repo.getLanguages(),
      repo.getCountries(),
      repo.getTrustLevels(),
      repo.getUsageRights(),
      repo.getMetadataQualities(),
      repo.getWorkflowStatuses(),
    ).wait;
    // Full (active + inactive) name maps, so a document that references a
    // deactivated category still renders its saved name.
    final allMains = await categories.getMainCategories();
    final allSubs = await categories.getSubCategories();
    return ReviewReferences(
      documentTypes: documentTypes,
      mainCategories: mainCategories,
      subCategories: subCategories,
      languages: languages,
      countries: countries,
      trustLevels: trustLevels,
      usageRights: usageRights,
      metadataQualities: metadataQualities,
      workflowStatuses: workflowStatuses,
      allMainNames: {for (final m in allMains) m.id: m.nameAr},
      allSubNames: {for (final s in allSubs) s.id: s.nameAr},
    );
  }
}

/// Arabic label for a workflow-status key.
String reviewWorkflowLabel(String key) => switch (key) {
  WorkflowStatusKey.imported => 'مستورد',
  WorkflowStatusKey.needsReview => 'يحتاج مراجعة',
  WorkflowStatusKey.inProgress => 'قيد التصنيف',
  WorkflowStatusKey.classified => 'مصنّف',
  WorkflowStatusKey.copiedToLibrary => 'نُسخ إلى المكتبة',
  WorkflowStatusKey.readyForExport => 'جاهز للتصدير',
  WorkflowStatusKey.archived => 'مؤرشف',
  _ => key,
};

/// Constrained thesis degree-type keys (mirrors the schema CHECK) with labels.
const Map<String, String> kDegreeTypeLabels = {
  'masters': 'ماجستير',
  'doctorate': 'دكتوراه',
  'other': 'أخرى',
};

/// Constrained legislation-type keys with labels.
const Map<String, String> kLegislationTypeLabels = {
  'ordinary_legislation': 'تشريع عادي',
  'regulation': 'لائحة',
  'executive_regulation': 'لائحة تنفيذية',
  'other': 'أخرى',
};

/// Constrained legislation effective-status keys with labels.
const Map<String, String> kEffectiveStatusLabels = {
  'active': 'ساري',
  'repealed': 'ملغى',
  'amended': 'معدَّل',
  'expired': 'منتهي النفاذ',
  'unknown': 'غير معروف',
};

/// Arabic label for a file-role key.
String reviewFileRoleLabel(String key) => switch (key) {
  FileRoleKey.sourceOriginal => 'ملف أصلي',
  FileRoleKey.managedCopy => 'نسخة مُدارة',
  FileRoleKey.convertedPdf => 'PDF محوّل',
  FileRoleKey.exportCopy => 'نسخة تصدير',
  _ => key,
};

/// Arabic label for a file-health key.
String reviewFileHealthLabel(String key) => switch (key) {
  FileHealthKey.healthy => 'سليم',
  FileHealthKey.corrupted => 'تالف',
  FileHealthKey.unreadable => 'غير قابل للقراءة',
  FileHealthKey.missing => 'مفقود',
  _ => 'غير معروف',
};

/// Arabic label for a conversion status key.
String reviewConversionStatusLabel(String key) => switch (key) {
  'conversion_approved' => 'تحويل معتمد',
  'needs_conversion_review' => 'يحتاج مراجعة التحويل',
  'conversion_failed' => 'فشل التحويل',
  'pending_conversion' => 'بانتظار التحويل',
  'converting' => 'جارٍ التحويل',
  _ => key,
};

/// Maps a structured [ValidationError] to a clear Arabic message. Never exposes
/// internal codes or stack traces; falls back to a generic sentence.
String reviewErrorMessage(ValidationError error) {
  switch (error.code) {
    case 'no_acceptable_file':
      return 'يلزم ملف PDF مصدري سليم أو نسخة PDF محوّلة معتمدة لاعتماد التصنيف.';
    case 'duplicate_classification':
      return 'لا يمكن تكرار نفس التصنيف أكثر من مرة.';
    case 'not_found':
      return 'المستند غير موجود.';
    case 'invalid_status':
      return 'لا يمكن تنفيذ هذه العملية على الحالة الحالية للمستند.';
  }
  final String label = _fieldLabel(error.field);
  final String reason = _reasonLabel(error.code);
  return '$label: $reason';
}

String _reasonLabel(String code) => switch (code) {
  'required' => 'حقل مطلوب',
  'too_long' => 'تجاوز الحد المسموح لعدد الأحرف',
  'invalid_chars' => 'يحتوي على رموز غير مسموحة',
  'invalid_date' => 'تاريخ غير صالح (YYYY-MM-DD)',
  'invalid_value' => 'قيمة غير مسموحة',
  'out_of_range' => 'خارج النطاق المسموح',
  'invalid_reference' => 'قيمة مرجعية غير صالحة أو غير مُفعّلة',
  'blank' => 'لا يمكن أن يكون فارغًا',
  _ => 'قيمة غير صالحة',
};

String _fieldLabel(String field) {
  // Normalize indexed keyword fields like `keywords[2]`.
  final String key = field.startsWith('keywords[') ? 'keywords' : field;
  return _fieldLabels[key] ?? key;
}

const Map<String, String> _fieldLabels = {
  'document': 'المستند',
  'workflowStatus': 'حالة سير العمل',
  'documentTypeId': 'نوع المستند',
  'title': 'العنوان',
  'languageKey': 'اللغة',
  'countryKey': 'الدولة',
  'trustLevelKey': 'مستوى الثقة',
  'usageRightsKey': 'حقوق الاستخدام',
  'metadataQualityKey': 'جودة البيانات الوصفية',
  'publicationYear': 'سنة النشر',
  'summary': 'الملخص',
  'sourceDescription': 'وصف المصدر',
  'reviewNotes': 'ملاحظات المراجعة',
  'primaryClassification': 'التصنيف الرئيسي',
  'primaryClassification.subCategoryId': 'الفئة الفرعية للتصنيف الرئيسي',
  'classifications': 'التصنيفات',
  'files': 'الملفات المصدرية',
  'keywords': 'الكلمات المفتاحية',
  'book.author': 'المؤلف',
  'book.publisher': 'الناشر',
  'book.publicationPlace': 'مكان النشر',
  'thesis.researcherName': 'اسم الباحث',
  'thesis.degreeTypeKey': 'نوع الدرجة العلمية',
  'thesis.universityName': 'الجامعة',
  'thesis.supervisorName': 'المشرف',
  'research.researcherName': 'اسم الباحث',
  'research.journalName': 'اسم المجلة',
  'research.publishingEntity': 'جهة النشر',
  'research.volume': 'المجلد',
  'research.issue': 'العدد',
  'research': 'اسم الباحث أو جهة النشر',
  'legislation.legislationTypeKey': 'نوع التشريع',
  'legislation.legislationTypeOther': 'نوع التشريع الآخر',
  'legislation.effectiveStatusKey': 'حالة النفاذ',
  'legislation.issueNumber': 'رقم العدد',
  'legislation.publicationDate': 'تاريخ النشر',
  'legislation.legislationNumber': 'رقم التشريع',
  'legislation.legislationYear': 'سنة التشريع',
  'legislation.effectiveDate': 'تاريخ النفاذ',
  'legislation.repealDate': 'تاريخ الإلغاء',
  'legislation': 'سنة النشر أو تاريخ النشر',
  'courtCase.courtName': 'اسم المحكمة',
  'courtCase.caseNumber': 'رقم القضية',
  'courtCase.judgmentDate': 'تاريخ الحكم',
  'courtCase.judgmentResult': 'نتيجة الحكم',
  'courtCase.legalPrinciple': 'المبدأ القانوني',
  'courtCase': 'نتيجة الحكم أو المبدأ القانوني',
  'report.publishingEntity': 'جهة النشر',
};
