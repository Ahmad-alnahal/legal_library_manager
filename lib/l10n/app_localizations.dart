import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ar')];

  /// No description provided for @appTitle.
  ///
  /// In ar, this message translates to:
  /// **'مرجعي'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'نظام الأرشفة المركزية'**
  String get appSubtitle;

  /// No description provided for @navDashboard.
  ///
  /// In ar, this message translates to:
  /// **'لوحة القيادة'**
  String get navDashboard;

  /// No description provided for @navImport.
  ///
  /// In ar, this message translates to:
  /// **'استيراد'**
  String get navImport;

  /// No description provided for @navDocuments.
  ///
  /// In ar, this message translates to:
  /// **'المستندات'**
  String get navDocuments;

  /// No description provided for @navReview.
  ///
  /// In ar, this message translates to:
  /// **'المراجعة والتصنيف'**
  String get navReview;

  /// No description provided for @navCategories.
  ///
  /// In ar, this message translates to:
  /// **'إدارة التصنيفات'**
  String get navCategories;

  /// No description provided for @navDuplicates.
  ///
  /// In ar, this message translates to:
  /// **'إدارة التكرارات'**
  String get navDuplicates;

  /// No description provided for @navSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get navSettings;

  /// No description provided for @navTooltipDashboard.
  ///
  /// In ar, this message translates to:
  /// **'لوحة القيادة: ملخص حالة الأرشفة'**
  String get navTooltipDashboard;

  /// No description provided for @navTooltipImport.
  ///
  /// In ar, this message translates to:
  /// **'استيراد: فحص المجلدات وحفظ المراجع'**
  String get navTooltipImport;

  /// No description provided for @navTooltipDocuments.
  ///
  /// In ar, this message translates to:
  /// **'المستندات: قائمة المستندات المفهرسة'**
  String get navTooltipDocuments;

  /// No description provided for @navTooltipReview.
  ///
  /// In ar, this message translates to:
  /// **'المراجعة والتصنيف: تصنيف المستندات واعتمادها'**
  String get navTooltipReview;

  /// No description provided for @navTooltipCategories.
  ///
  /// In ar, this message translates to:
  /// **'إدارة التصنيفات: الفئات الرئيسية والفرعية'**
  String get navTooltipCategories;

  /// No description provided for @navTooltipDuplicates.
  ///
  /// In ar, this message translates to:
  /// **'إدارة التكرارات: مراجعة الملفات المتطابقة'**
  String get navTooltipDuplicates;

  /// No description provided for @navTooltipSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات: المسارات والنسخ الاحتياطي والسياسات'**
  String get navTooltipSettings;

  /// No description provided for @navExpandTooltip.
  ///
  /// In ar, this message translates to:
  /// **'توسيع قائمة التنقل'**
  String get navExpandTooltip;

  /// No description provided for @navCollapseTooltip.
  ///
  /// In ar, this message translates to:
  /// **'تصغير قائمة التنقل'**
  String get navCollapseTooltip;

  /// No description provided for @dashboardTitle.
  ///
  /// In ar, this message translates to:
  /// **'ملخص العمليات'**
  String get dashboardTitle;

  /// No description provided for @dashboardSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'حالة الأرشفة المركزية للمستندات القانونية'**
  String get dashboardSubtitle;

  /// No description provided for @dashboardStaticNotice.
  ///
  /// In ar, this message translates to:
  /// **'أرقام عرض ثابتة لأغراض التصميم فقط، ولا تعكس بيانات فعلية بعد.'**
  String get dashboardStaticNotice;

  /// No description provided for @metricTotalImported.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المستورد'**
  String get metricTotalImported;

  /// No description provided for @metricNeedsReview.
  ///
  /// In ar, this message translates to:
  /// **'يحتاج مراجعة'**
  String get metricNeedsReview;

  /// No description provided for @metricInProgress.
  ///
  /// In ar, this message translates to:
  /// **'قيد المعالجة'**
  String get metricInProgress;

  /// No description provided for @metricClassified.
  ///
  /// In ar, this message translates to:
  /// **'تم التصنيف'**
  String get metricClassified;

  /// No description provided for @metricCopiedToLibrary.
  ///
  /// In ar, this message translates to:
  /// **'نُسخ إلى المكتبة'**
  String get metricCopiedToLibrary;

  /// No description provided for @metricReadyForExport.
  ///
  /// In ar, this message translates to:
  /// **'جاهز للتصدير المحلي'**
  String get metricReadyForExport;

  /// No description provided for @metricDuplicates.
  ///
  /// In ar, this message translates to:
  /// **'مكررات مكتشفة'**
  String get metricDuplicates;

  /// No description provided for @metricCorrupted.
  ///
  /// In ar, this message translates to:
  /// **'ملفات تالفة'**
  String get metricCorrupted;

  /// No description provided for @overallProgressTitle.
  ///
  /// In ar, this message translates to:
  /// **'تقدم الأرشفة الشامل'**
  String get overallProgressTitle;

  /// No description provided for @progressClassification.
  ///
  /// In ar, this message translates to:
  /// **'اكتمال التصنيف'**
  String get progressClassification;

  /// No description provided for @progressCopiedToLibrary.
  ///
  /// In ar, this message translates to:
  /// **'النسخ إلى المكتبة المدارة'**
  String get progressCopiedToLibrary;

  /// No description provided for @progressReadyForExport.
  ///
  /// In ar, this message translates to:
  /// **'جاهزية التصدير المحلي'**
  String get progressReadyForExport;

  /// No description provided for @importTitle.
  ///
  /// In ar, this message translates to:
  /// **'استيراد ملفات PDF'**
  String get importTitle;

  /// No description provided for @importSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'افحص واستورد مراجع المستندات القانونية من المجلدات المحلية.'**
  String get importSubtitle;

  /// No description provided for @sourceSafetyBannerTitle.
  ///
  /// In ar, this message translates to:
  /// **'أمان الملفات الأصلية'**
  String get sourceSafetyBannerTitle;

  /// No description provided for @sourceSafetyBannerBody.
  ///
  /// In ar, this message translates to:
  /// **'يقرأ النظام الملفات الأصلية فقط. لا ينقلها ولا يعيد تسميتها ولا يحذفها. يتم إنشاء نسخة داخل المكتبة المدارة بعد اعتماد التصنيف.'**
  String get sourceSafetyBannerBody;

  /// No description provided for @importScanOnlyNote.
  ///
  /// In ar, this message translates to:
  /// **'الاستيراد يحفظ المراجع وقيم SHA-256 فقط، ولا ينسخ الملفات إلى المكتبة المدارة.'**
  String get importScanOnlyNote;

  /// No description provided for @importEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج استيراد بعد'**
  String get importEmptyTitle;

  /// No description provided for @importEmptyBody.
  ///
  /// In ar, this message translates to:
  /// **'اختر مجلد مصدر وابدأ الفحص لعرض المستندات المكتشفة هنا.'**
  String get importEmptyBody;

  /// No description provided for @documentsTitle.
  ///
  /// In ar, this message translates to:
  /// **'المستندات المؤرشفة'**
  String get documentsTitle;

  /// No description provided for @documentsSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'قائمة المستندات المفهرسة مع البحث والتصفية.'**
  String get documentsSubtitle;

  /// No description provided for @documentsSearchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث في المستندات...'**
  String get documentsSearchHint;

  /// No description provided for @documentsFilterButton.
  ///
  /// In ar, this message translates to:
  /// **'تصفية'**
  String get documentsFilterButton;

  /// No description provided for @documentsFilterStatus.
  ///
  /// In ar, this message translates to:
  /// **'الحالة'**
  String get documentsFilterStatus;

  /// No description provided for @documentsFilterType.
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get documentsFilterType;

  /// No description provided for @documentsFilterCategory.
  ///
  /// In ar, this message translates to:
  /// **'الفئة القانونية'**
  String get documentsFilterCategory;

  /// No description provided for @documentsFilterYear.
  ///
  /// In ar, this message translates to:
  /// **'سنة الإصدار'**
  String get documentsFilterYear;

  /// No description provided for @documentsEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد مستندات لعرضها'**
  String get documentsEmptyTitle;

  /// No description provided for @documentsEmptyBody.
  ///
  /// In ar, this message translates to:
  /// **'ستظهر المستندات هنا بعد استيرادها وفهرستها.'**
  String get documentsEmptyBody;

  /// No description provided for @duplicatesTitle.
  ///
  /// In ar, this message translates to:
  /// **'إدارة التكرارات'**
  String get duplicatesTitle;

  /// No description provided for @duplicatesSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'مراجعة الملفات المتطابقة بقيمة SHA-256 على مستوى الفهرسة فقط.'**
  String get duplicatesSubtitle;

  /// No description provided for @duplicatesSafetyTitle.
  ///
  /// In ar, this message translates to:
  /// **'البيانات المصدرية محمية'**
  String get duplicatesSafetyTitle;

  /// No description provided for @duplicatesSafetyBody.
  ///
  /// In ar, this message translates to:
  /// **'تتم مراجعة النسخ المكررة لتوحيد الفهرسة فقط. لا يُحذف أو يُعدّل أو يُنقل أي ملف أصلي. اختر النسخة المفضلة لتوجيه عمليات البحث المستقبلية.'**
  String get duplicatesSafetyBody;

  /// No description provided for @duplicatesEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد مجموعات تكرار'**
  String get duplicatesEmptyTitle;

  /// No description provided for @duplicatesEmptyBody.
  ///
  /// In ar, this message translates to:
  /// **'تظهر هنا مجموعات الملفات المتطابقة بقيمة SHA-256 بعد الاستيراد.'**
  String get duplicatesEmptyBody;

  /// No description provided for @settingsTitle.
  ///
  /// In ar, this message translates to:
  /// **'إعدادات النظام'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'تكوين مسارات المكتبة والنسخ الاحتياطي وسياسات حماية البيانات الأصلية.'**
  String get settingsSubtitle;

  /// No description provided for @settingsCopyPolicyTitle.
  ///
  /// In ar, this message translates to:
  /// **'سياسة «نسخ فقط»'**
  String get settingsCopyPolicyTitle;

  /// No description provided for @settingsCopyPolicyBody.
  ///
  /// In ar, this message translates to:
  /// **'يقرأ النظام الملفات الأصلية فقط. لا ينقلها ولا يعيد تسميتها ولا يحذفها. يتم إنشاء نسخة داخل المكتبة المدارة بعد اعتماد التصنيف.'**
  String get settingsCopyPolicyBody;

  /// No description provided for @settingsCopyPolicyActive.
  ///
  /// In ar, this message translates to:
  /// **'سياسة نشطة ومفروضة'**
  String get settingsCopyPolicyActive;

  /// No description provided for @settingsManagedLibraryTitle.
  ///
  /// In ar, this message translates to:
  /// **'مجلد المكتبة المدارة'**
  String get settingsManagedLibraryTitle;

  /// No description provided for @settingsManagedLibraryBody.
  ///
  /// In ar, this message translates to:
  /// **'الموقع المركزي حيث تُخزَّن نسخ المستندات القانونية المؤرشفة.'**
  String get settingsManagedLibraryBody;

  /// No description provided for @settingsDatabaseTitle.
  ///
  /// In ar, this message translates to:
  /// **'موقع قاعدة البيانات'**
  String get settingsDatabaseTitle;

  /// No description provided for @settingsDatabaseBody.
  ///
  /// In ar, this message translates to:
  /// **'تخزين البيانات الوصفية وهيكل الفهرسة محليًا.'**
  String get settingsDatabaseBody;

  /// No description provided for @settingsBackupTitle.
  ///
  /// In ar, this message translates to:
  /// **'النسخ الاحتياطي'**
  String get settingsBackupTitle;

  /// No description provided for @settingsBackupBody.
  ///
  /// In ar, this message translates to:
  /// **'نسخ احتياطية محلية لقاعدة البيانات والبيانات الوصفية.'**
  String get settingsBackupBody;

  /// No description provided for @settingsActionChangeLocation.
  ///
  /// In ar, this message translates to:
  /// **'تغيير الموقع'**
  String get settingsActionChangeLocation;

  /// No description provided for @settingsActionChooseLocation.
  ///
  /// In ar, this message translates to:
  /// **'اختيار الموقع'**
  String get settingsActionChooseLocation;

  /// No description provided for @settingsActionVerifyStructure.
  ///
  /// In ar, this message translates to:
  /// **'التحقق من الهيكل'**
  String get settingsActionVerifyStructure;

  /// No description provided for @settingsPlaceholderNote.
  ///
  /// In ar, this message translates to:
  /// **'ستتوفر خيارات الإعداد التفصيلية في مرحلة لاحقة.'**
  String get settingsPlaceholderNote;

  /// No description provided for @statusBadgePlaceholder.
  ///
  /// In ar, this message translates to:
  /// **'قيد الإنشاء'**
  String get statusBadgePlaceholder;

  /// No description provided for @importSourceFolderTitle.
  ///
  /// In ar, this message translates to:
  /// **'مجلد المصدر'**
  String get importSourceFolderTitle;

  /// No description provided for @importFolderFieldEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم اختيار مجلد بعد'**
  String get importFolderFieldEmpty;

  /// No description provided for @importPickFolderButton.
  ///
  /// In ar, this message translates to:
  /// **'اختيار مجلد'**
  String get importPickFolderButton;

  /// No description provided for @importRecursiveLabel.
  ///
  /// In ar, this message translates to:
  /// **'تضمين المجلدات الفرعية'**
  String get importRecursiveLabel;

  /// No description provided for @importStartButton.
  ///
  /// In ar, this message translates to:
  /// **'بدء الفحص والاستيراد'**
  String get importStartButton;

  /// No description provided for @importCancelButton.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get importCancelButton;

  /// No description provided for @importRetryButton.
  ///
  /// In ar, this message translates to:
  /// **'إعادة محاولة الملفات المتعذّرة'**
  String get importRetryButton;

  /// No description provided for @importResetButton.
  ///
  /// In ar, this message translates to:
  /// **'استيراد جديد'**
  String get importResetButton;

  /// No description provided for @importProgressTitle.
  ///
  /// In ar, this message translates to:
  /// **'تقدم الاستيراد'**
  String get importProgressTitle;

  /// No description provided for @importPhaseValidating.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التحقق من المجلد'**
  String get importPhaseValidating;

  /// No description provided for @importPhaseScanning.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ فحص الملفات'**
  String get importPhaseScanning;

  /// No description provided for @importPhaseImporting.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الاستيراد'**
  String get importPhaseImporting;

  /// No description provided for @importPhaseFinalizing.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ إنهاء الدفعة'**
  String get importPhaseFinalizing;

  /// No description provided for @importPhaseCancelling.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الإلغاء'**
  String get importPhaseCancelling;

  /// No description provided for @importProgressCount.
  ///
  /// In ar, this message translates to:
  /// **'تمت معالجة {processed} من {discovered}'**
  String importProgressCount(int processed, int discovered);

  /// No description provided for @importCurrentFileLabel.
  ///
  /// In ar, this message translates to:
  /// **'الملف الحالي'**
  String get importCurrentFileLabel;

  /// No description provided for @importSummaryTitle.
  ///
  /// In ar, this message translates to:
  /// **'ملخص الاستيراد'**
  String get importSummaryTitle;

  /// No description provided for @importSummaryNew.
  ///
  /// In ar, this message translates to:
  /// **'مستندات جديدة'**
  String get importSummaryNew;

  /// No description provided for @importSummaryDuplicates.
  ///
  /// In ar, this message translates to:
  /// **'نسخ مكررة'**
  String get importSummaryDuplicates;

  /// No description provided for @importSummaryAlreadyImported.
  ///
  /// In ar, this message translates to:
  /// **'مستوردة مسبقًا'**
  String get importSummaryAlreadyImported;

  /// No description provided for @importSummaryFailed.
  ///
  /// In ar, this message translates to:
  /// **'ملفات متعذّرة'**
  String get importSummaryFailed;

  /// No description provided for @importResultsTitle.
  ///
  /// In ar, this message translates to:
  /// **'نتائج الملفات'**
  String get importResultsTitle;

  /// No description provided for @importResultsEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم اكتشاف ملفات PDF في هذا المجلد.'**
  String get importResultsEmpty;

  /// No description provided for @importCompletedTitle.
  ///
  /// In ar, this message translates to:
  /// **'اكتمل الاستيراد'**
  String get importCompletedTitle;

  /// No description provided for @importCancelledTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء الاستيراد'**
  String get importCancelledTitle;

  /// No description provided for @importCancelledNote.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ دفعة جزئية. يمكنك بدء استيراد جديد أو إعادة المحاولة.'**
  String get importCancelledNote;

  /// No description provided for @importFailedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الاستيراد'**
  String get importFailedTitle;

  /// No description provided for @importFailedGenericBody.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع أثناء الاستيراد. لم تتأثر الملفات الأصلية.'**
  String get importFailedGenericBody;

  /// No description provided for @importStatusImportedNew.
  ///
  /// In ar, this message translates to:
  /// **'مستند جديد'**
  String get importStatusImportedNew;

  /// No description provided for @importStatusImportedDuplicate.
  ///
  /// In ar, this message translates to:
  /// **'نسخة مكررة'**
  String get importStatusImportedDuplicate;

  /// No description provided for @importStatusAlreadyImported.
  ///
  /// In ar, this message translates to:
  /// **'مستوردة مسبقًا'**
  String get importStatusAlreadyImported;

  /// No description provided for @importStatusUnsupported.
  ///
  /// In ar, this message translates to:
  /// **'نوع غير مدعوم'**
  String get importStatusUnsupported;

  /// No description provided for @importStatusUnreadable.
  ///
  /// In ar, this message translates to:
  /// **'غير قابل للقراءة'**
  String get importStatusUnreadable;

  /// No description provided for @importStatusHashFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر حساب البصمة'**
  String get importStatusHashFailed;

  /// No description provided for @importStatusScanFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الفحص'**
  String get importStatusScanFailed;

  /// No description provided for @importStatusPersistenceFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر حفظ السجل'**
  String get importStatusPersistenceFailed;

  /// No description provided for @importStatusCorrupted.
  ///
  /// In ar, this message translates to:
  /// **'ملف تالف'**
  String get importStatusCorrupted;

  /// No description provided for @importValidationDoesNotExist.
  ///
  /// In ar, this message translates to:
  /// **'المجلد غير موجود.'**
  String get importValidationDoesNotExist;

  /// No description provided for @importValidationNotADirectory.
  ///
  /// In ar, this message translates to:
  /// **'المسار المحدد ليس مجلدًا.'**
  String get importValidationNotADirectory;

  /// No description provided for @importValidationNotReadable.
  ///
  /// In ar, this message translates to:
  /// **'تعذّرت قراءة المجلد.'**
  String get importValidationNotReadable;

  /// No description provided for @importValidationIsProtectedRoot.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن اختيار مجلد محمي تابع للنظام.'**
  String get importValidationIsProtectedRoot;

  /// No description provided for @importValidationInsideProtectedRoot.
  ///
  /// In ar, this message translates to:
  /// **'المجلد يقع داخل مجلد محمي تابع للنظام.'**
  String get importValidationInsideProtectedRoot;

  /// No description provided for @importValidationContainsProtectedRoot.
  ///
  /// In ar, this message translates to:
  /// **'المجلد يحتوي على مجلد محمي تابع للنظام مثل المكتبة المدارة.'**
  String get importValidationContainsProtectedRoot;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
