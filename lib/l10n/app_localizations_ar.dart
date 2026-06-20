// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مرجعي';

  @override
  String get appSubtitle => 'نظام الأرشفة المركزية';

  @override
  String get navDashboard => 'لوحة القيادة';

  @override
  String get navImport => 'استيراد';

  @override
  String get navDocuments => 'المستندات';

  @override
  String get navReview => 'المراجعة والتصنيف';

  @override
  String get navCategories => 'إدارة التصنيفات';

  @override
  String get navDuplicates => 'إدارة التكرارات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get navTooltipDashboard => 'لوحة القيادة: ملخص حالة الأرشفة';

  @override
  String get navTooltipImport => 'استيراد: فحص المجلدات وحفظ المراجع';

  @override
  String get navTooltipDocuments => 'المستندات: قائمة المستندات المفهرسة';

  @override
  String get navTooltipReview => 'المراجعة والتصنيف: تصنيف المستندات واعتمادها';

  @override
  String get navTooltipCategories =>
      'إدارة التصنيفات: الفئات الرئيسية والفرعية';

  @override
  String get navTooltipDuplicates =>
      'إدارة التكرارات: مراجعة الملفات المتطابقة';

  @override
  String get navTooltipSettings =>
      'الإعدادات: المسارات والنسخ الاحتياطي والسياسات';

  @override
  String get navExpandTooltip => 'توسيع قائمة التنقل';

  @override
  String get navCollapseTooltip => 'تصغير قائمة التنقل';

  @override
  String get dashboardTitle => 'ملخص العمليات';

  @override
  String get dashboardSubtitle => 'حالة الأرشفة المركزية للمستندات القانونية';

  @override
  String get dashboardStaticNotice =>
      'أرقام عرض ثابتة لأغراض التصميم فقط، ولا تعكس بيانات فعلية بعد.';

  @override
  String get metricTotalImported => 'إجمالي المستورد';

  @override
  String get metricNeedsReview => 'يحتاج مراجعة';

  @override
  String get metricInProgress => 'قيد المعالجة';

  @override
  String get metricClassified => 'تم التصنيف';

  @override
  String get metricCopiedToLibrary => 'نُسخ إلى المكتبة';

  @override
  String get metricReadyForExport => 'جاهز للتصدير المحلي';

  @override
  String get metricDuplicates => 'مكررات مكتشفة';

  @override
  String get metricCorrupted => 'ملفات تالفة';

  @override
  String get overallProgressTitle => 'تقدم الأرشفة الشامل';

  @override
  String get progressClassification => 'اكتمال التصنيف';

  @override
  String get progressCopiedToLibrary => 'النسخ إلى المكتبة المدارة';

  @override
  String get progressReadyForExport => 'جاهزية التصدير المحلي';

  @override
  String get importTitle => 'استيراد ملفات PDF';

  @override
  String get importSubtitle =>
      'افحص واستورد مراجع المستندات القانونية من المجلدات المحلية.';

  @override
  String get sourceSafetyBannerTitle => 'أمان الملفات الأصلية';

  @override
  String get sourceSafetyBannerBody =>
      'يقرأ النظام الملفات الأصلية فقط. لا ينقلها ولا يعيد تسميتها ولا يحذفها. يتم إنشاء نسخة داخل المكتبة المدارة بعد اعتماد التصنيف.';

  @override
  String get importScanOnlyNote =>
      'الاستيراد يحفظ المراجع وقيم SHA-256 فقط، ولا ينسخ الملفات إلى المكتبة المدارة.';

  @override
  String get importEmptyTitle => 'لا توجد نتائج استيراد بعد';

  @override
  String get importEmptyBody =>
      'اختر مجلد مصدر وابدأ الفحص لعرض المستندات المكتشفة هنا.';

  @override
  String get documentsTitle => 'المستندات المؤرشفة';

  @override
  String get documentsSubtitle => 'قائمة المستندات المفهرسة مع البحث والتصفية.';

  @override
  String get documentsSearchHint => 'ابحث في المستندات...';

  @override
  String get documentsFilterButton => 'تصفية';

  @override
  String get documentsFilterStatus => 'الحالة';

  @override
  String get documentsFilterType => 'النوع';

  @override
  String get documentsFilterCategory => 'الفئة القانونية';

  @override
  String get documentsFilterYear => 'سنة الإصدار';

  @override
  String get documentsEmptyTitle => 'لا توجد مستندات لعرضها';

  @override
  String get documentsEmptyBody =>
      'ستظهر المستندات هنا بعد استيرادها وفهرستها.';

  @override
  String get duplicatesTitle => 'إدارة التكرارات';

  @override
  String get duplicatesSubtitle =>
      'مراجعة الملفات المتطابقة بقيمة SHA-256 على مستوى الفهرسة فقط.';

  @override
  String get duplicatesSafetyTitle => 'البيانات المصدرية محمية';

  @override
  String get duplicatesSafetyBody =>
      'تتم مراجعة النسخ المكررة لتوحيد الفهرسة فقط. لا يُحذف أو يُعدّل أو يُنقل أي ملف أصلي. اختر النسخة المفضلة لتوجيه عمليات البحث المستقبلية.';

  @override
  String get duplicatesEmptyTitle => 'لا توجد مجموعات تكرار';

  @override
  String get duplicatesEmptyBody =>
      'تظهر هنا مجموعات الملفات المتطابقة بقيمة SHA-256 بعد الاستيراد.';

  @override
  String get duplicatesGroupsLabel => 'مجموعات التكرار';

  @override
  String get duplicatesMembersLabel => 'الملفات المتطابقة';

  @override
  String get duplicatesSelectGroupPrompt =>
      'اختر مجموعة من القائمة لعرض الملفات المتطابقة';

  @override
  String get duplicatesLoadError => 'تعذّر تحميل مجموعات التكرار';

  @override
  String get duplicatesRetry => 'إعادة المحاولة';

  @override
  String get duplicatesSha256Label => 'SHA-256';

  @override
  String get duplicatesPreferredBadge => 'مفضّل';

  @override
  String get duplicatesHiddenFromSearchLabel => 'مخفي من البحث';

  @override
  String get duplicatesDocumentCode => 'رمز المستند';

  @override
  String duplicatesFileCountLabel(int count) {
    return '$count ملفات متطابقة';
  }

  @override
  String get duplicatesSnackPreferredSaved => 'تم تعيين النسخة المفضلة.';

  @override
  String get duplicatesSnackMemberHidden =>
      'تم إخفاء هذه النسخة من نتائج البحث.';

  @override
  String get duplicatesSnackMemberUnhidden =>
      'تم إظهار هذه النسخة في نتائج البحث.';

  @override
  String get duplicatesSnackReviewSaved => 'تم حفظ مراجعة مجموعة التكرار.';

  @override
  String get duplicatesSnackPreferredFailed =>
      'تعذّر تعيين النسخة المفضلة بأمان.';

  @override
  String get duplicatesSnackVisibilityFailed =>
      'تعذّر تحديث ظهور النسخة بأمان.';

  @override
  String get duplicatesSnackReviewSaveFailed =>
      'تعذّر حفظ مراجعة المجموعة بأمان.';

  @override
  String get duplicatesSnackGenericFailed =>
      'تعذّر تحديث مجموعة التكرار بأمان.';

  @override
  String get duplicatesReviewStatusLabel => 'حالة المراجعة';

  @override
  String get duplicatesReviewNotesLabel => 'ملاحظات المراجعة';

  @override
  String get duplicatesSaveReview => 'حفظ المراجعة';

  @override
  String get duplicatesSaving => 'جارٍ الحفظ';

  @override
  String get duplicatesSetPreferred => 'تعيين كمفضلة';

  @override
  String get duplicatesAlreadyPreferred => 'النسخة المفضلة';

  @override
  String get duplicatesShowInSearch => 'إظهار في البحث';

  @override
  String get duplicatesHideFromSearch => 'إخفاء من البحث';

  @override
  String get settingsTitle => 'إعدادات النظام';

  @override
  String get settingsSubtitle =>
      'تكوين مسارات المكتبة والنسخ الاحتياطي وسياسات حماية البيانات الأصلية.';

  @override
  String get settingsCopyPolicyTitle => 'سياسة «نسخ فقط»';

  @override
  String get settingsCopyPolicyBody =>
      'يقرأ النظام الملفات الأصلية فقط. لا ينقلها ولا يعيد تسميتها ولا يحذفها. يتم إنشاء نسخة داخل المكتبة المدارة بعد اعتماد التصنيف.';

  @override
  String get settingsCopyPolicyActive => 'سياسة نشطة ومفروضة';

  @override
  String get settingsManagedLibraryTitle => 'مجلد المكتبة المدارة';

  @override
  String get settingsManagedLibraryBody =>
      'الموقع المركزي حيث تُخزَّن نسخ المستندات القانونية المؤرشفة.';

  @override
  String get settingsDatabaseTitle => 'موقع قاعدة البيانات';

  @override
  String get settingsDatabaseBody =>
      'تخزين البيانات الوصفية وهيكل الفهرسة محليًا.';

  @override
  String get settingsBackupTitle => 'النسخ الاحتياطي';

  @override
  String get settingsBackupBody =>
      'نسخ احتياطية محلية لقاعدة البيانات والبيانات الوصفية.';

  @override
  String get settingsActionChangeLocation => 'تغيير الموقع';

  @override
  String get settingsActionChooseLocation => 'اختيار الموقع';

  @override
  String get settingsActionVerifyStructure => 'التحقق من الهيكل';

  @override
  String get settingsPlaceholderNote =>
      'ستتوفر خيارات الإعداد التفصيلية في مرحلة لاحقة.';

  @override
  String get statusBadgePlaceholder => 'قيد الإنشاء';

  @override
  String get importSourceFolderTitle => 'مجلد المصدر';

  @override
  String get importFolderFieldEmpty => 'لم يتم اختيار مجلد بعد';

  @override
  String get importPickFolderButton => 'اختيار مجلد';

  @override
  String get importRecursiveLabel => 'تضمين المجلدات الفرعية';

  @override
  String get importStartButton => 'بدء الفحص والاستيراد';

  @override
  String get importCancelButton => 'إلغاء';

  @override
  String get importRetryButton => 'إعادة محاولة الملفات المتعذّرة';

  @override
  String get importResetButton => 'استيراد جديد';

  @override
  String get importProgressTitle => 'تقدم الاستيراد';

  @override
  String get importPhaseValidating => 'جارٍ التحقق من المجلد';

  @override
  String get importPhaseScanning => 'جارٍ فحص الملفات';

  @override
  String get importPhaseImporting => 'جارٍ الاستيراد';

  @override
  String get importPhaseFinalizing => 'جارٍ إنهاء الدفعة';

  @override
  String get importPhaseCancelling => 'جارٍ الإلغاء';

  @override
  String importProgressCount(int processed, int discovered) {
    return 'تمت معالجة $processed من $discovered';
  }

  @override
  String get importCurrentFileLabel => 'الملف الحالي';

  @override
  String get importSummaryTitle => 'ملخص الاستيراد';

  @override
  String get importSummaryNew => 'مستندات جديدة';

  @override
  String get importSummaryDuplicates => 'نسخ مكررة';

  @override
  String get importSummaryAlreadyImported => 'مستوردة مسبقًا';

  @override
  String get importSummaryFailed => 'ملفات متعذّرة';

  @override
  String get importResultsTitle => 'نتائج الملفات';

  @override
  String get importResultsEmpty => 'لم يتم اكتشاف ملفات PDF في هذا المجلد.';

  @override
  String get importCompletedTitle => 'اكتمل الاستيراد';

  @override
  String get importCancelledTitle => 'تم إلغاء الاستيراد';

  @override
  String get importCancelledNote =>
      'تم حفظ دفعة جزئية. يمكنك بدء استيراد جديد أو إعادة المحاولة.';

  @override
  String get importFailedTitle => 'تعذّر الاستيراد';

  @override
  String get importFailedGenericBody =>
      'حدث خطأ غير متوقع أثناء الاستيراد. لم تتأثر الملفات الأصلية.';

  @override
  String get importStatusImportedNew => 'مستند جديد';

  @override
  String get importStatusImportedDuplicate => 'نسخة مكررة';

  @override
  String get importStatusAlreadyImported => 'مستوردة مسبقًا';

  @override
  String get importStatusUnsupported => 'نوع غير مدعوم';

  @override
  String get importStatusUnreadable => 'غير قابل للقراءة';

  @override
  String get importStatusHashFailed => 'تعذّر حساب البصمة';

  @override
  String get importStatusScanFailed => 'تعذّر الفحص';

  @override
  String get importStatusPersistenceFailed => 'تعذّر حفظ السجل';

  @override
  String get importStatusCorrupted => 'ملف تالف';

  @override
  String get importValidationDoesNotExist => 'المجلد غير موجود.';

  @override
  String get importValidationNotADirectory => 'المسار المحدد ليس مجلدًا.';

  @override
  String get importValidationNotReadable => 'تعذّرت قراءة المجلد.';

  @override
  String get importValidationIsProtectedRoot =>
      'لا يمكن اختيار مجلد محمي تابع للنظام.';

  @override
  String get importValidationInsideProtectedRoot =>
      'المجلد يقع داخل مجلد محمي تابع للنظام.';

  @override
  String get importValidationContainsProtectedRoot =>
      'المجلد يحتوي على مجلد محمي تابع للنظام مثل المكتبة المدارة.';

  @override
  String get startupLoading => 'جارٍ تجهيز مرجعي...';

  @override
  String get startupFailureTitle => 'تعذّر تجهيز قاعدة البيانات المحلية';

  @override
  String get startupFailureBody =>
      'لم يتمكّن مرجعي من إكمال تهيئة البيانات المحلية. يمكنك إعادة المحاولة بأمان. إذا استمرت المشكلة، أغلق التطبيق واحتفظ بنسخة من قاعدة البيانات قبل إجراء أي صيانة.';

  @override
  String get startupSafetyNote => 'لم يتم نقل أي ملف أصلي أو تعديله أو حذفه.';

  @override
  String get startupRetry => 'إعادة المحاولة';

  @override
  String get fileOpenOpenFile => 'فتح الملف';

  @override
  String get fileOpenOpenFolder => 'فتح المجلد';

  @override
  String get fileOpenOpening => 'جاري الفتح';

  @override
  String get fileOpenSuccessFile => 'تم فتح الملف.';

  @override
  String get fileOpenSuccessFolder => 'تم فتح مجلد الملف.';

  @override
  String get fileOpenAuditFailureFile =>
      'تم فتح الملف، لكن تعذّر تسجيل حدث الفتح في السجل.';

  @override
  String get fileOpenAuditFailureFolder =>
      'تم فتح المجلد، لكن تعذّر تسجيل حدث الفتح في السجل.';

  @override
  String get fileOpenErrorRecordNotFound => 'لا يوجد سجل مسجل لهذا الملف.';

  @override
  String get fileOpenErrorMissingPath => 'مسار الملف غير مسجل.';

  @override
  String get fileOpenErrorPathNotFound => 'الملف غير موجود في مساره المسجل.';

  @override
  String get fileOpenErrorNotRegularFile => 'المسار لا يشير إلى ملف عادي.';

  @override
  String get fileOpenErrorUnsupportedExtension =>
      'نوع الملف غير مدعوم أو لا يطابق الامتداد المسجل.';

  @override
  String get fileOpenErrorPermissionDenied => 'تم رفض الإذن بفتح الملف.';

  @override
  String get fileOpenErrorNoAssociatedApplication =>
      'لا يوجد تطبيق مرتبط بهذا النوع من الملفات.';

  @override
  String get fileOpenErrorOsLaunchFailed =>
      'تعذّر فتح الملف. لم تتأثر الملفات الأصلية.';

  @override
  String get fileOpenErrorUnhealthyFile =>
      'لا يمكن فتح الملف مباشرةً؛ الملف تالف أو غير قابل للقراءة أو مفقود. يمكنك فتح المجلد بدلًا من ذلك.';
}
