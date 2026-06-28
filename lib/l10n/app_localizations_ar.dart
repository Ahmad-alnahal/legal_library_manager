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
  String get dashboardLoadingMessage => 'جارٍ تحميل بيانات لوحة القيادة...';

  @override
  String get dashboardErrorMessage => 'تعذّر تحميل بيانات لوحة القيادة.';

  @override
  String get dashboardRetry => 'إعادة المحاولة';

  @override
  String get dashboardRefreshTooltip => 'تحديث البيانات';

  @override
  String get dashboardActivityTitle => 'النشاط الأخير';

  @override
  String get dashboardActivityEmpty => 'لا يوجد نشاط مسجّل بعد.';

  @override
  String get dashboardActivityFileEvent => 'حدث ملف';

  @override
  String get dashboardActivityOpenEvent => 'فتح ملف';

  @override
  String get dashboardActivityImportBatch => 'دفعة استيراد';

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
  String get importTitle => 'استيراد ملفات PDF وWord';

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
  String get importSummaryPairedWordSource => 'مصادر Word مقترنة';

  @override
  String get importSummaryFailed => 'ملفات متعذّرة';

  @override
  String get importResultsTitle => 'نتائج الملفات';

  @override
  String get importResultsEmpty =>
      'لم يتم اكتشاف ملفات PDF أو Word في هذا المجلد.';

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
  String get importStatusPairedWordSource => 'مصدر Word مقترن بـ PDF';

  @override
  String get importStatusInterrupted => 'مقاطع (أُعيد تشغيل التطبيق)';

  @override
  String get importBannerRunning => 'جارٍ الاستيراد';

  @override
  String get importBannerCancelling => 'جارٍ الإلغاء...';

  @override
  String get importBannerCompleted => 'اكتمل الاستيراد';

  @override
  String get importBannerCancelled => 'تم إلغاء الاستيراد';

  @override
  String get importBannerFailed => 'فشل الاستيراد';

  @override
  String importBannerProgress(int processed, int discovered) {
    return '$processed من $discovered';
  }

  @override
  String get importBannerGoToImport => 'انتقل إلى الاستيراد';

  @override
  String get importBannerCancel => 'إلغاء الاستيراد';

  @override
  String get importBannerDismiss => 'إغلاق';

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

  @override
  String get settingsCopyLocationsTitle => 'مواقع النسخ الآمن';

  @override
  String get settingsCopyLocationsBody =>
      'تُحفظ ملفات PDF المدارة داخل مجلد files، وتبقى النسخ الاحتياطية في مجلد منفصل. يجهّز التطبيق هذه المواقع تلقائيًا، ويمكن تغييرها كخيار متقدم.';

  @override
  String get settingsCopyLocationsWarning =>
      'تغيير المواقع لا ينقل الملفات المدارة أو النسخ الاحتياطية السابقة؛ تبقى في مكانها الحالي.';

  @override
  String get settingsManagedRootTitle => 'جذر المكتبة المدارة';

  @override
  String get settingsBackupRootTitle => 'مجلد النسخ الاحتياطي لقاعدة البيانات';

  @override
  String get settingsResetToDefaults => 'استخدام المجلدات الافتراضية';

  @override
  String get settingsResetWarning =>
      'تغيير المسارات إلى الافتراضي لا ينقل الملفات المدارة أو النسخ الاحتياطية من مواقعها الحالية.';

  @override
  String get settingsAttentionBannerBody =>
      'يتطلب إعداد مواقع النسخ الآمن انتباهك. يبقى النسخ إلى المكتبة المدارة متوقفًا حتى يكتمل الإعداد، دون أي تأثير على الملفات الحالية.';

  @override
  String get settingsLocationNotChosen => 'لم يتم الاختيار بعد';

  @override
  String get settingsRecreateFolder => 'إعادة إنشاء المجلد';

  @override
  String get settingsChooseButton => 'اختيار';

  @override
  String get settingsChangeButton => 'تغيير';

  @override
  String get settingsStatusAutomatic => 'مُهيأ تلقائيًا';

  @override
  String get settingsStatusCustom => 'موقع مخصص';

  @override
  String get settingsStatusMissing => 'المجلد غير متاح — يتطلب الانتباه';

  @override
  String get settingsStatusNotConfigured => 'غير مُهيأ بعد';

  @override
  String get settingsDialogCancel => 'إلغاء';

  @override
  String get settingsDialogRecreateTitle => 'إعادة إنشاء المجلد';

  @override
  String get settingsDialogRecreateContent =>
      'سيتم إنشاء المجلد المفقود في نفس المسار المُهيأ فقط، بعد التحقق من سلامته. لا يتم نقل أو نسخ أو تعديل أو حذف أي ملفات موجودة.';

  @override
  String get settingsDialogRecreateConfirm => 'إعادة الإنشاء';

  @override
  String get settingsDialogResetTitle => 'استخدام المجلدات الافتراضية';

  @override
  String get settingsDialogResetContent =>
      'سيتم تعيين مجلدَي المكتبة المدارة والنسخ الاحتياطي إلى المواقع الافتراضية لمرجعي داخل مجلد المستندات.\n\nتنبيه: هذا لا ينقل الملفات المدارة أو النسخ الاحتياطية السابقة؛ تبقى في مواقعها الحالية ولا يتأثر أي ملف موجود.';

  @override
  String get settingsDialogResetConfirm => 'تطبيق الافتراضي';

  @override
  String settingsDialogChangeTitle(String label) {
    return 'تغيير $label';
  }

  @override
  String get settingsDialogChangeContent =>
      'بعد اختيار المجلد الجديد، سيتم حفظه فقط إذا اجتاز التحقق من السلامة.\n\nالملفات المدارة والنسخ الاحتياطية الحالية تبقى في مواقعها الأصلية ولا يُنقل أو يُحذف أي ملف موجود.';

  @override
  String get settingsDialogChangeContinue => 'متابعة واختيار مجلد';

  @override
  String get settingsSnackSaved =>
      'تم حفظ مواقع المكتبة المدارة والنسخ الاحتياطي بأمان.';

  @override
  String get settingsSnackChooseBoth =>
      'اختر مجلدي المكتبة المدارة والنسخ الاحتياطي.';

  @override
  String get settingsSnackUnsafeOverlap =>
      'يجب أن تكون المجلدات منفصلة عن بعضها وعن قاعدة البيانات.';

  @override
  String get settingsSnackRecreated =>
      'تمت إعادة إنشاء المجلد المفقود بأمان دون أي تغيير على الملفات الحالية.';

  @override
  String get settingsSnackRecreateUnsafe =>
      'تعذّرت إعادة الإنشاء: يجب أن يكون المجلد منفصلًا عن المجلدات الأخرى وقاعدة البيانات ومجلدات المصدر.';

  @override
  String get settingsSnackRecreateInvalid =>
      'تعذّرت إعادة الإنشاء: مسار المجلد المُهيأ غير صالح.';

  @override
  String get settingsSnackRecreateFailed =>
      'تعذّرت إعادة إنشاء المجلد. يبقى الإعداد بحاجة إلى الانتباه دون أي تغيير على الملفات الحالية.';

  @override
  String get settingsSnackDefaultsApplied =>
      'تم تطبيق المجلدات الافتراضية لمرجعي. الملفات المدارة والنسخ الاحتياطية السابقة في مواقعها الأصلية.';

  @override
  String get settingsSnackDefaultsResolutionFailed =>
      'تعذّر تحديد مجلد المستندات. تحقق من صلاحيات النظام.';

  @override
  String get settingsSnackDefaultsCreationFailed =>
      'تعذّر إنشاء المجلدات الافتراضية. تحقق من المساحة المتاحة وصلاحيات الكتابة.';

  @override
  String get settingsSnackFallback =>
      'تعذّر اعتماد المجلد المحدد. اختر مجلدًا موجودًا وآمنًا.';

  @override
  String get settingsManualBackupTitle =>
      'النسخ الاحتياطي اليدوي لقاعدة البيانات';

  @override
  String get settingsManualBackupBody =>
      'تُنشئ نسخة احتياطية من سجلات قاعدة بيانات مرجعي (البيانات الوصفية والتصنيفات فقط) في مجلد النسخ الاحتياطي المُهيأ. الملفات القانونية الأصلية وملفات PDF المدارة لا تُدرج في النسخة الاحتياطية ولا تتأثر.';

  @override
  String get settingsManualBackupButton => 'إنشاء نسخة احتياطية';

  @override
  String get settingsManualBackupDialogTitle =>
      'إنشاء نسخة احتياطية من قاعدة البيانات';

  @override
  String get settingsManualBackupDialogContent =>
      'سيتم نسخ قاعدة البيانات المحلية (البيانات الوصفية فقط) إلى مجلد النسخ الاحتياطي المُهيأ.\n\nالملفات القانونية الأصلية وملفات PDF المدارة لا تُدرج في النسخة الاحتياطية ولا يتأثر أي ملف موجود.';

  @override
  String get settingsManualBackupDialogConfirm => 'إنشاء النسخة';

  @override
  String get settingsSnackBackupSuccess => 'تم إنشاء النسخة الاحتياطية بنجاح.';

  @override
  String get settingsSnackBackupNotConfigured =>
      'لم يتم تهيئة مجلد النسخ الاحتياطي. اختر مجلدًا من إعدادات المواقع أدناه.';

  @override
  String get settingsSnackBackupRootMissing =>
      'مجلد النسخ الاحتياطي غير متاح. أعد إنشاءه أو اختر مجلدًا آخر من الإعدادات.';

  @override
  String get settingsSnackBackupFailed =>
      'تعذّر إنشاء النسخة الاحتياطية. تحقق من مساحة القرص وصلاحيات الكتابة.';

  @override
  String settingsStartupRecoveryAttention(int count) {
    return 'توجد ملفات عمل غير مكتملة داخل مجلدات مرجعي تحتاج إلى مراجعة آمنة قبل متابعة النسخ. عدد العناصر: $count. لم يتم نقل أو حذف أي ملف.';
  }

  @override
  String get settingsRecoveryReviewButton => 'مراجعة';

  @override
  String get settingsRecoveryReviewDialogTitle => 'مراجعة ملفات الاسترداد';

  @override
  String settingsRecoveryReviewCopyingCount(int count) {
    return 'ملفات نسخ مؤقتة: $count (مؤهلة للحذف)';
  }

  @override
  String settingsRecoveryReviewBackupCount(int count) {
    return 'نسخ احتياطية منقوصة: $count (مؤهلة للحذف)';
  }

  @override
  String settingsRecoveryReviewUnregisteredCount(int count) {
    return 'ملفات PDF غير مسجلة: $count (تحتاج مراجعة يدوية)';
  }

  @override
  String get settingsRecoveryReviewCleanupButton => 'حذف الملفات المؤهلة';

  @override
  String get settingsRecoveryReviewConfirmTitle => 'تأكيد الحذف الآمن';

  @override
  String get settingsRecoveryReviewConfirmContent =>
      'سيتم حذف ملفات النسخ المؤقتة وملفات النسخ الاحتياطية المنقوصة فقط.\n\nلن تُمس ملفات PDF المسجلة أو الملفات الأصلية.';

  @override
  String get settingsRecoveryReviewConfirmAction => 'حذف الآن';

  @override
  String get settingsRecoveryReviewLoadFailed =>
      'تعذّر تحميل تقرير الاسترداد. حاول مرة أخرى.';

  @override
  String get settingsSnackRecoveryCleaned => 'تم حذف الملفات المؤهلة بنجاح.';

  @override
  String get settingsSnackRecoveryPartialFailure =>
      'اكتمل الحذف جزئياً. تعذّر حذف بعض الملفات.';

  @override
  String get settingsSnackRecoveryFailed =>
      'تعذّر الحذف. تحقق من صلاحيات الوصول.';

  @override
  String get settingsSnackRecoveryNothingToClean =>
      'لا توجد ملفات مؤهلة للحذف الآمن.';

  @override
  String get settingsIntegrityTitle => 'سلامة النسخ المدارة';

  @override
  String get settingsIntegrityBody =>
      'يفحص هذا الاختبار جميع ملفات PDF المسجلة في مكتبة مرجعي ويكتشف الملفات المفقودة أو التي تغيّر محتواها. لا يُعدّل الملفات على القرص ولا يُنشئها.';

  @override
  String get settingsIntegrityButton => 'فحص النسخ المدارة';

  @override
  String get settingsSnackIntegrityClean => 'جميع النسخ المدارة سليمة.';

  @override
  String settingsSnackIntegrityIssues(int count) {
    return 'اكتُشف $count ملف مشكل في النسخ المدارة.';
  }

  @override
  String get settingsSnackIntegrityFailed =>
      'تعذّر فحص النسخ المدارة. حاول مرة أخرى.';

  @override
  String get settingsSnackUnauthorized => 'هذه العملية تتطلب صلاحيات المشرف.';

  @override
  String get duplicatesReviewStatusReviewed => 'تمت المراجعة';

  @override
  String get duplicatesReviewStatusDeferred => 'مؤجلة';

  @override
  String get duplicatesReviewStatusUnreviewed => 'غير مراجعة';

  @override
  String dashboardRelativeDays(int n) {
    return '$nي';
  }

  @override
  String dashboardRelativeHours(int n) {
    return '$nس';
  }

  @override
  String dashboardRelativeMinutes(int n) {
    return '$nد';
  }

  @override
  String get dashboardRelativeNow => 'الآن';

  @override
  String get loginTitle => 'تسجيل الدخول';

  @override
  String get loginUsernameLabel => 'اسم المستخدم';

  @override
  String get loginPasswordLabel => 'كلمة المرور';

  @override
  String get loginSubmitButton => 'دخول';

  @override
  String get loginShowPasswordTooltip => 'إظهار كلمة المرور';

  @override
  String get loginHidePasswordTooltip => 'إخفاء كلمة المرور';

  @override
  String get loginErrorInvalidCredentials =>
      'اسم المستخدم أو كلمة المرور غير صحيحة.';

  @override
  String get loginErrorAccountSuspended => 'تم تعليق الحساب. تواصل مع المدير.';

  @override
  String loginErrorDelay(int seconds) {
    return 'يرجى الانتظار $seconds ثانية قبل المحاولة مرة أخرى.';
  }

  @override
  String get setupTitle => 'إعداد حساب المدير';

  @override
  String get setupSubtitle => 'قم بإنشاء كلمة مرور آمنة لحساب مدير النظام.';

  @override
  String get setupPasswordLabel => 'كلمة المرور الجديدة';

  @override
  String get setupConfirmPasswordLabel => 'تأكيد كلمة المرور';

  @override
  String get setupPasswordHint => '8 أحرف على الأقل';

  @override
  String get setupSubmitButton => 'تعيين كلمة المرور';

  @override
  String get setupErrorPasswordMismatch => 'كلمتا المرور غير متطابقتين.';

  @override
  String get setupErrorPasswordTooShort =>
      'كلمة المرور قصيرة جدًا. الحد الأدنى 8 أحرف.';

  @override
  String get setupErrorUnexpected =>
      'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';

  @override
  String get setupRecoveryKeyTitle => 'مفتاح الاسترداد';

  @override
  String get setupRecoveryKeyBody =>
      'احتفظ بمفتاح الاسترداد هذا في مكان آمن بعيد عن الجهاز. هذه هي المرة الوحيدة التي يُعرض فيها. ستحتاجه لاستعادة حساب المدير إذا نسيت كلمة المرور.';

  @override
  String get setupRecoveryKeyCopyButton => 'نسخ المفتاح';

  @override
  String get setupRecoveryKeyCopied => 'تم نسخ مفتاح الاسترداد.';

  @override
  String get setupRecoveryKeyConfirmLabel =>
      'لقد حفظت مفتاح الاسترداد في مكان آمن';

  @override
  String get setupContinueButton => 'الدخول إلى التطبيق';

  @override
  String get setupInProgress => 'جارٍ إعداد الحساب...';

  @override
  String get loginRecoveryLinkButton => 'نسيت كلمة مرور المدير؟';

  @override
  String get recoveryTitle => 'استعادة حساب المدير';

  @override
  String get recoverySubtitle =>
      'أدخل مفتاح الاسترداد لإعادة تعيين كلمة المرور.';

  @override
  String get recoveryKeyLabel => 'مفتاح الاسترداد';

  @override
  String get recoveryKeyHint => 'XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX';

  @override
  String get recoverySubmitButton => 'تأكيد';

  @override
  String get recoveryErrorInvalidKey => 'مفتاح الاسترداد غير صحيح.';

  @override
  String recoveryErrorThrottled(int seconds) {
    return 'يرجى الانتظار $seconds ثانية قبل المحاولة مرة أخرى.';
  }

  @override
  String get recoveryErrorUnexpected =>
      'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';

  @override
  String get recoverySuccessTitle => 'تمت الاستعادة بنجاح';

  @override
  String get recoverySuccessBody =>
      'تم إعادة تعيين حساب المدير. احتفظ بمفتاح الاسترداد الجديد في مكان آمن — هذه هي المرة الوحيدة التي يُعرض فيها.';

  @override
  String get recoverySuccessCopyButton => 'نسخ المفتاح';

  @override
  String get recoverySuccessCopied => 'تم نسخ مفتاح الاسترداد.';

  @override
  String get recoverySuccessConfirmLabel =>
      'لقد حفظت مفتاح الاسترداد الجديد في مكان آمن';

  @override
  String get recoveryContinueButton => 'العودة لتسجيل الدخول';

  @override
  String get navAdministration => 'إدارة الحسابات';

  @override
  String get navTooltipAdministration => 'إدارة حسابات المشغلين';

  @override
  String get passwordChangeTitle => 'تغيير كلمة المرور';

  @override
  String get passwordChangeSubtitle =>
      'يجب تغيير كلمة المرور المؤقتة قبل المتابعة.';

  @override
  String get passwordChangeCurrentLabel => 'كلمة المرور الحالية';

  @override
  String get passwordChangeNewLabel => 'كلمة المرور الجديدة';

  @override
  String get passwordChangeConfirmLabel => 'تأكيد كلمة المرور الجديدة';

  @override
  String get passwordChangeSubmitButton => 'تغيير كلمة المرور';

  @override
  String get passwordChangeErrorIncorrectCurrent =>
      'كلمة المرور الحالية غير صحيحة.';

  @override
  String get accountManagementTitle => 'إدارة الحسابات';

  @override
  String get accountManagementCreateButton => 'حساب جديد';

  @override
  String get accountManagementAdminSection => 'حساب المدير';

  @override
  String get accountManagementOperatorsSection => 'حسابات المشغلين';

  @override
  String get accountManagementNoOperators => 'لا توجد حسابات مشغلين بعد.';

  @override
  String get accountManagementDisplayNameLabel => 'الاسم المعروض';

  @override
  String get accountManagementTempPasswordLabel => 'كلمة المرور المؤقتة';

  @override
  String get accountManagementCreateDialogTitle => 'إنشاء حساب مشغل';

  @override
  String get accountManagementIssueTempPasswordTitle => 'إصدار كلمة مرور مؤقتة';

  @override
  String accountManagementIssueTempPasswordBody(String operatorName) {
    return 'إصدار كلمة مرور مؤقتة للمشغل: $operatorName';
  }

  @override
  String get accountManagementCancelButton => 'إلغاء';

  @override
  String get accountManagementCreateConfirmButton => 'إنشاء';

  @override
  String get accountManagementConfirmButton => 'تأكيد';

  @override
  String get accountManagementLogoutButton => 'تسجيل الخروج';

  @override
  String get accountManagementLogoutDialogTitle => 'تسجيل الخروج';

  @override
  String get accountManagementLogoutDialogBody =>
      'هل تريد تسجيل الخروج من الحساب الحالي؟';

  @override
  String get accountManagementLogoutDialogConfirm => 'تسجيل الخروج';

  @override
  String get accountManagementErrorDuplicateUsername =>
      'اسم المستخدم هذا مستخدم بالفعل.';

  @override
  String get accountManagementErrorUnauthorized =>
      'غير مصرح بهذه العملية. يُرجى إعادة تسجيل الدخول.';

  @override
  String get accountStatusActive => 'نشط';

  @override
  String get accountStatusSuspended => 'موقوف';

  @override
  String get accountStatusDisabled => 'معطّل';

  @override
  String get accountActionSuspend => 'تعليق الحساب';

  @override
  String get accountActionReactivate => 'إعادة تفعيل';

  @override
  String get accountActionIssueTempPassword => 'إصدار كلمة مرور مؤقتة';

  @override
  String get adminTabAccounts => 'الحسابات';

  @override
  String get adminTabAuditLog => 'سجل الأمان';

  @override
  String get auditLogTitle => 'سجل الأمان';

  @override
  String get auditLogSubtitle =>
      'سجل دائم لجميع أحداث الأمان، مرتبة من الأحدث إلى الأقدم.';

  @override
  String get auditLogEmpty => 'لا توجد أحداث مسجلة بعد.';

  @override
  String get auditLogLoadMore => 'تحميل المزيد';

  @override
  String get auditLogErrorBody => 'تعذّر تحميل سجل الأمان.';

  @override
  String get auditLogRetry => 'إعادة المحاولة';

  @override
  String get auditActorSystem => 'النظام';

  @override
  String get auditActorAdmin => 'المدير';

  @override
  String get auditEventAdminBootstrapped => 'تهيئة حساب المدير';

  @override
  String get auditEventPasswordChanged => 'تغيير كلمة المرور';

  @override
  String get auditEventLoginSuccess => 'تسجيل دخول ناجح';

  @override
  String get auditEventLoginFailed => 'محاولة دخول فاشلة';

  @override
  String get auditEventAccountCreated => 'إنشاء حساب مشغل';

  @override
  String get auditEventAccountSuspended => 'تعليق حساب';

  @override
  String get auditEventAccountReactivated => 'إعادة تفعيل حساب';

  @override
  String get auditEventTempPasswordIssued => 'إصدار كلمة مرور مؤقتة';

  @override
  String get auditEventAccountAutoSuspended =>
      'تعليق تلقائي بسبب محاولات متكررة';

  @override
  String get auditEventRecoveryKeyRedeemed => 'استخدام مفتاح الاسترداد';

  @override
  String get auditEventUnknown => 'حدث غير معروف';

  @override
  String get auditEventStepUpGranted => 'تحقق من هوية المدير';

  @override
  String get auditEventStepUpDenied => 'محاولة تحقق فاشلة';

  @override
  String get stepUpDialogTitle => 'التحقق من هوية المدير';

  @override
  String get stepUpDialogSubtitle => 'أدخل كلمة مرور المدير للمتابعة.';

  @override
  String get stepUpPasswordLabel => 'كلمة المرور';

  @override
  String get stepUpVerifyButton => 'تحقق';

  @override
  String get stepUpCancelButton => 'إلغاء';

  @override
  String get stepUpErrorWrongPassword =>
      'كلمة المرور غير صحيحة. حاول مرة أخرى.';

  @override
  String get stepUpErrorUnexpected => 'حدث خطأ غير متوقع. حاول مرة أخرى.';

  @override
  String get settingsSnackStepUpRequired =>
      'يجب التحقق من هوية المدير أولاً قبل تنفيذ هذه العملية.';

  @override
  String get conversionWorkTitle => 'تحويل مستندات Word';

  @override
  String get conversionWorkSubtitle =>
      'تظهر هنا ملفات Word التي تنتظر التحويل أو تحتاج إلى إعادة محاولة.';

  @override
  String get conversionWorkEmpty => 'لا توجد ملفات Word بانتظار التحويل.';

  @override
  String get conversionWorkLoadError => 'تعذّر تحميل قائمة ملفات Word.';

  @override
  String get conversionWorkRun => 'تحويل';

  @override
  String get conversionWorkRetry => 'إعادة محاولة';

  @override
  String get conversionWorkStatusPending => 'جاهز للتحويل';

  @override
  String get conversionWorkStatusConverting => 'جارٍ التحويل';

  @override
  String get conversionWorkStatusFailed => 'فشل التحويل';

  @override
  String get conversionWorkStatusUnknown => 'حالة غير معروفة';

  @override
  String get conversionWorkSnackRunSucceeded =>
      'تم تحويل الملف. راجع جودة PDF المحوّل.';

  @override
  String get conversionWorkSnackRunBlocked =>
      'تعذّر بدء التحويل حالياً. تحقق من توفر المحوّل ثم حاول مرة أخرى.';

  @override
  String get conversionWorkSnackRunFailed =>
      'فشل التحويل. يمكنك إعادة المحاولة بعد معالجة السبب.';

  @override
  String get conversionWorkStagePreparing => 'جارٍ التحضير';

  @override
  String get conversionWorkStageOpeningDocument => 'جارٍ فتح مستند Word';

  @override
  String get conversionWorkStageExportingPdf => 'جارٍ تصدير PDF';

  @override
  String get conversionWorkStageValidatingOutput =>
      'جارٍ التحقق من الملف الناتج';

  @override
  String get conversionWorkStageSavingResult => 'جارٍ حفظ النتيجة';

  @override
  String get conversionWorkStageCleaningUp => 'جارٍ تنظيف الملفات المؤقتة';

  @override
  String conversionWorkQueueProgress(int completed, int total) {
    return '$completed من $total ملفات اكتملت';
  }

  @override
  String get importHistoryTitle => 'سجل الاستيراد';

  @override
  String get importHistoryEmpty => 'لا توجد عمليات استيراد سابقة.';

  @override
  String get importHistoryStatusCompleted => 'مكتمل';

  @override
  String get importHistoryStatusFailed => 'فشل';

  @override
  String get importHistoryStatusCancelled => 'ملغى';

  @override
  String get importHistoryStatusInterrupted => 'انقطع';

  @override
  String get importHistoryInterruptedNote =>
      'توقف الاستيراد بسبب إغلاق التطبيق. الاستئناف التلقائي غير مدعوم حالياً.';

  @override
  String get importHistoryReuseFolder => 'استيراد جديد من نفس المجلد';

  @override
  String importHistoryStartedAt(String time) {
    return 'بدأ في $time';
  }

  @override
  String importHistorySummaryLine(int imported, int failed, int discovered) {
    return '$imported جديد · $failed متعذّر · $discovered مكتشف';
  }
}
