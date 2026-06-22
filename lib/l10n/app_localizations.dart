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

  /// No description provided for @dashboardLoadingMessage.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ تحميل بيانات لوحة القيادة...'**
  String get dashboardLoadingMessage;

  /// No description provided for @dashboardErrorMessage.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل بيانات لوحة القيادة.'**
  String get dashboardErrorMessage;

  /// No description provided for @dashboardRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get dashboardRetry;

  /// No description provided for @dashboardRefreshTooltip.
  ///
  /// In ar, this message translates to:
  /// **'تحديث البيانات'**
  String get dashboardRefreshTooltip;

  /// No description provided for @dashboardActivityTitle.
  ///
  /// In ar, this message translates to:
  /// **'النشاط الأخير'**
  String get dashboardActivityTitle;

  /// No description provided for @dashboardActivityEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد نشاط مسجّل بعد.'**
  String get dashboardActivityEmpty;

  /// No description provided for @dashboardActivityFileEvent.
  ///
  /// In ar, this message translates to:
  /// **'حدث ملف'**
  String get dashboardActivityFileEvent;

  /// No description provided for @dashboardActivityOpenEvent.
  ///
  /// In ar, this message translates to:
  /// **'فتح ملف'**
  String get dashboardActivityOpenEvent;

  /// No description provided for @dashboardActivityImportBatch.
  ///
  /// In ar, this message translates to:
  /// **'دفعة استيراد'**
  String get dashboardActivityImportBatch;

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

  /// No description provided for @duplicatesGroupsLabel.
  ///
  /// In ar, this message translates to:
  /// **'مجموعات التكرار'**
  String get duplicatesGroupsLabel;

  /// No description provided for @duplicatesMembersLabel.
  ///
  /// In ar, this message translates to:
  /// **'الملفات المتطابقة'**
  String get duplicatesMembersLabel;

  /// No description provided for @duplicatesSelectGroupPrompt.
  ///
  /// In ar, this message translates to:
  /// **'اختر مجموعة من القائمة لعرض الملفات المتطابقة'**
  String get duplicatesSelectGroupPrompt;

  /// No description provided for @duplicatesLoadError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل مجموعات التكرار'**
  String get duplicatesLoadError;

  /// No description provided for @duplicatesRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get duplicatesRetry;

  /// No description provided for @duplicatesSha256Label.
  ///
  /// In ar, this message translates to:
  /// **'SHA-256'**
  String get duplicatesSha256Label;

  /// No description provided for @duplicatesPreferredBadge.
  ///
  /// In ar, this message translates to:
  /// **'مفضّل'**
  String get duplicatesPreferredBadge;

  /// No description provided for @duplicatesHiddenFromSearchLabel.
  ///
  /// In ar, this message translates to:
  /// **'مخفي من البحث'**
  String get duplicatesHiddenFromSearchLabel;

  /// No description provided for @duplicatesDocumentCode.
  ///
  /// In ar, this message translates to:
  /// **'رمز المستند'**
  String get duplicatesDocumentCode;

  /// No description provided for @duplicatesFileCountLabel.
  ///
  /// In ar, this message translates to:
  /// **'{count} ملفات متطابقة'**
  String duplicatesFileCountLabel(int count);

  /// No description provided for @duplicatesSnackPreferredSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم تعيين النسخة المفضلة.'**
  String get duplicatesSnackPreferredSaved;

  /// No description provided for @duplicatesSnackMemberHidden.
  ///
  /// In ar, this message translates to:
  /// **'تم إخفاء هذه النسخة من نتائج البحث.'**
  String get duplicatesSnackMemberHidden;

  /// No description provided for @duplicatesSnackMemberUnhidden.
  ///
  /// In ar, this message translates to:
  /// **'تم إظهار هذه النسخة في نتائج البحث.'**
  String get duplicatesSnackMemberUnhidden;

  /// No description provided for @duplicatesSnackReviewSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ مراجعة مجموعة التكرار.'**
  String get duplicatesSnackReviewSaved;

  /// No description provided for @duplicatesSnackPreferredFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تعيين النسخة المفضلة بأمان.'**
  String get duplicatesSnackPreferredFailed;

  /// No description provided for @duplicatesSnackVisibilityFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحديث ظهور النسخة بأمان.'**
  String get duplicatesSnackVisibilityFailed;

  /// No description provided for @duplicatesSnackReviewSaveFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر حفظ مراجعة المجموعة بأمان.'**
  String get duplicatesSnackReviewSaveFailed;

  /// No description provided for @duplicatesSnackGenericFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحديث مجموعة التكرار بأمان.'**
  String get duplicatesSnackGenericFailed;

  /// No description provided for @duplicatesReviewStatusLabel.
  ///
  /// In ar, this message translates to:
  /// **'حالة المراجعة'**
  String get duplicatesReviewStatusLabel;

  /// No description provided for @duplicatesReviewNotesLabel.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات المراجعة'**
  String get duplicatesReviewNotesLabel;

  /// No description provided for @duplicatesSaveReview.
  ///
  /// In ar, this message translates to:
  /// **'حفظ المراجعة'**
  String get duplicatesSaveReview;

  /// No description provided for @duplicatesSaving.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الحفظ'**
  String get duplicatesSaving;

  /// No description provided for @duplicatesSetPreferred.
  ///
  /// In ar, this message translates to:
  /// **'تعيين كمفضلة'**
  String get duplicatesSetPreferred;

  /// No description provided for @duplicatesAlreadyPreferred.
  ///
  /// In ar, this message translates to:
  /// **'النسخة المفضلة'**
  String get duplicatesAlreadyPreferred;

  /// No description provided for @duplicatesShowInSearch.
  ///
  /// In ar, this message translates to:
  /// **'إظهار في البحث'**
  String get duplicatesShowInSearch;

  /// No description provided for @duplicatesHideFromSearch.
  ///
  /// In ar, this message translates to:
  /// **'إخفاء من البحث'**
  String get duplicatesHideFromSearch;

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

  /// No description provided for @startupLoading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ تجهيز مرجعي...'**
  String get startupLoading;

  /// No description provided for @startupFailureTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تجهيز قاعدة البيانات المحلية'**
  String get startupFailureTitle;

  /// No description provided for @startupFailureBody.
  ///
  /// In ar, this message translates to:
  /// **'لم يتمكّن مرجعي من إكمال تهيئة البيانات المحلية. يمكنك إعادة المحاولة بأمان. إذا استمرت المشكلة، أغلق التطبيق واحتفظ بنسخة من قاعدة البيانات قبل إجراء أي صيانة.'**
  String get startupFailureBody;

  /// No description provided for @startupSafetyNote.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم نقل أي ملف أصلي أو تعديله أو حذفه.'**
  String get startupSafetyNote;

  /// No description provided for @startupRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get startupRetry;

  /// No description provided for @fileOpenOpenFile.
  ///
  /// In ar, this message translates to:
  /// **'فتح الملف'**
  String get fileOpenOpenFile;

  /// No description provided for @fileOpenOpenFolder.
  ///
  /// In ar, this message translates to:
  /// **'فتح المجلد'**
  String get fileOpenOpenFolder;

  /// No description provided for @fileOpenOpening.
  ///
  /// In ar, this message translates to:
  /// **'جاري الفتح'**
  String get fileOpenOpening;

  /// No description provided for @fileOpenSuccessFile.
  ///
  /// In ar, this message translates to:
  /// **'تم فتح الملف.'**
  String get fileOpenSuccessFile;

  /// No description provided for @fileOpenSuccessFolder.
  ///
  /// In ar, this message translates to:
  /// **'تم فتح مجلد الملف.'**
  String get fileOpenSuccessFolder;

  /// No description provided for @fileOpenAuditFailureFile.
  ///
  /// In ar, this message translates to:
  /// **'تم فتح الملف، لكن تعذّر تسجيل حدث الفتح في السجل.'**
  String get fileOpenAuditFailureFile;

  /// No description provided for @fileOpenAuditFailureFolder.
  ///
  /// In ar, this message translates to:
  /// **'تم فتح المجلد، لكن تعذّر تسجيل حدث الفتح في السجل.'**
  String get fileOpenAuditFailureFolder;

  /// No description provided for @fileOpenErrorRecordNotFound.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد سجل مسجل لهذا الملف.'**
  String get fileOpenErrorRecordNotFound;

  /// No description provided for @fileOpenErrorMissingPath.
  ///
  /// In ar, this message translates to:
  /// **'مسار الملف غير مسجل.'**
  String get fileOpenErrorMissingPath;

  /// No description provided for @fileOpenErrorPathNotFound.
  ///
  /// In ar, this message translates to:
  /// **'الملف غير موجود في مساره المسجل.'**
  String get fileOpenErrorPathNotFound;

  /// No description provided for @fileOpenErrorNotRegularFile.
  ///
  /// In ar, this message translates to:
  /// **'المسار لا يشير إلى ملف عادي.'**
  String get fileOpenErrorNotRegularFile;

  /// No description provided for @fileOpenErrorUnsupportedExtension.
  ///
  /// In ar, this message translates to:
  /// **'نوع الملف غير مدعوم أو لا يطابق الامتداد المسجل.'**
  String get fileOpenErrorUnsupportedExtension;

  /// No description provided for @fileOpenErrorPermissionDenied.
  ///
  /// In ar, this message translates to:
  /// **'تم رفض الإذن بفتح الملف.'**
  String get fileOpenErrorPermissionDenied;

  /// No description provided for @fileOpenErrorNoAssociatedApplication.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد تطبيق مرتبط بهذا النوع من الملفات.'**
  String get fileOpenErrorNoAssociatedApplication;

  /// No description provided for @fileOpenErrorOsLaunchFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر فتح الملف. لم تتأثر الملفات الأصلية.'**
  String get fileOpenErrorOsLaunchFailed;

  /// No description provided for @fileOpenErrorUnhealthyFile.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن فتح الملف مباشرةً؛ الملف تالف أو غير قابل للقراءة أو مفقود. يمكنك فتح المجلد بدلًا من ذلك.'**
  String get fileOpenErrorUnhealthyFile;

  /// No description provided for @settingsCopyLocationsTitle.
  ///
  /// In ar, this message translates to:
  /// **'مواقع النسخ الآمن'**
  String get settingsCopyLocationsTitle;

  /// No description provided for @settingsCopyLocationsBody.
  ///
  /// In ar, this message translates to:
  /// **'تُحفظ ملفات PDF المدارة داخل مجلد files، وتبقى النسخ الاحتياطية في مجلد منفصل. يجهّز التطبيق هذه المواقع تلقائيًا، ويمكن تغييرها كخيار متقدم.'**
  String get settingsCopyLocationsBody;

  /// No description provided for @settingsCopyLocationsWarning.
  ///
  /// In ar, this message translates to:
  /// **'تغيير المواقع لا ينقل الملفات المدارة أو النسخ الاحتياطية السابقة؛ تبقى في مكانها الحالي.'**
  String get settingsCopyLocationsWarning;

  /// No description provided for @settingsManagedRootTitle.
  ///
  /// In ar, this message translates to:
  /// **'جذر المكتبة المدارة'**
  String get settingsManagedRootTitle;

  /// No description provided for @settingsBackupRootTitle.
  ///
  /// In ar, this message translates to:
  /// **'مجلد النسخ الاحتياطي لقاعدة البيانات'**
  String get settingsBackupRootTitle;

  /// No description provided for @settingsResetToDefaults.
  ///
  /// In ar, this message translates to:
  /// **'استخدام المجلدات الافتراضية'**
  String get settingsResetToDefaults;

  /// No description provided for @settingsResetWarning.
  ///
  /// In ar, this message translates to:
  /// **'تغيير المسارات إلى الافتراضي لا ينقل الملفات المدارة أو النسخ الاحتياطية من مواقعها الحالية.'**
  String get settingsResetWarning;

  /// No description provided for @settingsAttentionBannerBody.
  ///
  /// In ar, this message translates to:
  /// **'يتطلب إعداد مواقع النسخ الآمن انتباهك. يبقى النسخ إلى المكتبة المدارة متوقفًا حتى يكتمل الإعداد، دون أي تأثير على الملفات الحالية.'**
  String get settingsAttentionBannerBody;

  /// No description provided for @settingsLocationNotChosen.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم الاختيار بعد'**
  String get settingsLocationNotChosen;

  /// No description provided for @settingsRecreateFolder.
  ///
  /// In ar, this message translates to:
  /// **'إعادة إنشاء المجلد'**
  String get settingsRecreateFolder;

  /// No description provided for @settingsChooseButton.
  ///
  /// In ar, this message translates to:
  /// **'اختيار'**
  String get settingsChooseButton;

  /// No description provided for @settingsChangeButton.
  ///
  /// In ar, this message translates to:
  /// **'تغيير'**
  String get settingsChangeButton;

  /// No description provided for @settingsStatusAutomatic.
  ///
  /// In ar, this message translates to:
  /// **'مُهيأ تلقائيًا'**
  String get settingsStatusAutomatic;

  /// No description provided for @settingsStatusCustom.
  ///
  /// In ar, this message translates to:
  /// **'موقع مخصص'**
  String get settingsStatusCustom;

  /// No description provided for @settingsStatusMissing.
  ///
  /// In ar, this message translates to:
  /// **'المجلد غير متاح — يتطلب الانتباه'**
  String get settingsStatusMissing;

  /// No description provided for @settingsStatusNotConfigured.
  ///
  /// In ar, this message translates to:
  /// **'غير مُهيأ بعد'**
  String get settingsStatusNotConfigured;

  /// No description provided for @settingsDialogCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get settingsDialogCancel;

  /// No description provided for @settingsDialogRecreateTitle.
  ///
  /// In ar, this message translates to:
  /// **'إعادة إنشاء المجلد'**
  String get settingsDialogRecreateTitle;

  /// No description provided for @settingsDialogRecreateContent.
  ///
  /// In ar, this message translates to:
  /// **'سيتم إنشاء المجلد المفقود في نفس المسار المُهيأ فقط، بعد التحقق من سلامته. لا يتم نقل أو نسخ أو تعديل أو حذف أي ملفات موجودة.'**
  String get settingsDialogRecreateContent;

  /// No description provided for @settingsDialogRecreateConfirm.
  ///
  /// In ar, this message translates to:
  /// **'إعادة الإنشاء'**
  String get settingsDialogRecreateConfirm;

  /// No description provided for @settingsDialogResetTitle.
  ///
  /// In ar, this message translates to:
  /// **'استخدام المجلدات الافتراضية'**
  String get settingsDialogResetTitle;

  /// No description provided for @settingsDialogResetContent.
  ///
  /// In ar, this message translates to:
  /// **'سيتم تعيين مجلدَي المكتبة المدارة والنسخ الاحتياطي إلى المواقع الافتراضية لمرجعي داخل مجلد المستندات.\n\nتنبيه: هذا لا ينقل الملفات المدارة أو النسخ الاحتياطية السابقة؛ تبقى في مواقعها الحالية ولا يتأثر أي ملف موجود.'**
  String get settingsDialogResetContent;

  /// No description provided for @settingsDialogResetConfirm.
  ///
  /// In ar, this message translates to:
  /// **'تطبيق الافتراضي'**
  String get settingsDialogResetConfirm;

  /// No description provided for @settingsDialogChangeTitle.
  ///
  /// In ar, this message translates to:
  /// **'تغيير {label}'**
  String settingsDialogChangeTitle(String label);

  /// No description provided for @settingsDialogChangeContent.
  ///
  /// In ar, this message translates to:
  /// **'بعد اختيار المجلد الجديد، سيتم حفظه فقط إذا اجتاز التحقق من السلامة.\n\nالملفات المدارة والنسخ الاحتياطية الحالية تبقى في مواقعها الأصلية ولا يُنقل أو يُحذف أي ملف موجود.'**
  String get settingsDialogChangeContent;

  /// No description provided for @settingsDialogChangeContinue.
  ///
  /// In ar, this message translates to:
  /// **'متابعة واختيار مجلد'**
  String get settingsDialogChangeContinue;

  /// No description provided for @settingsSnackSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ مواقع المكتبة المدارة والنسخ الاحتياطي بأمان.'**
  String get settingsSnackSaved;

  /// No description provided for @settingsSnackChooseBoth.
  ///
  /// In ar, this message translates to:
  /// **'اختر مجلدي المكتبة المدارة والنسخ الاحتياطي.'**
  String get settingsSnackChooseBoth;

  /// No description provided for @settingsSnackUnsafeOverlap.
  ///
  /// In ar, this message translates to:
  /// **'يجب أن تكون المجلدات منفصلة عن بعضها وعن قاعدة البيانات.'**
  String get settingsSnackUnsafeOverlap;

  /// No description provided for @settingsSnackRecreated.
  ///
  /// In ar, this message translates to:
  /// **'تمت إعادة إنشاء المجلد المفقود بأمان دون أي تغيير على الملفات الحالية.'**
  String get settingsSnackRecreated;

  /// No description provided for @settingsSnackRecreateUnsafe.
  ///
  /// In ar, this message translates to:
  /// **'تعذّرت إعادة الإنشاء: يجب أن يكون المجلد منفصلًا عن المجلدات الأخرى وقاعدة البيانات ومجلدات المصدر.'**
  String get settingsSnackRecreateUnsafe;

  /// No description provided for @settingsSnackRecreateInvalid.
  ///
  /// In ar, this message translates to:
  /// **'تعذّرت إعادة الإنشاء: مسار المجلد المُهيأ غير صالح.'**
  String get settingsSnackRecreateInvalid;

  /// No description provided for @settingsSnackRecreateFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّرت إعادة إنشاء المجلد. يبقى الإعداد بحاجة إلى الانتباه دون أي تغيير على الملفات الحالية.'**
  String get settingsSnackRecreateFailed;

  /// No description provided for @settingsSnackDefaultsApplied.
  ///
  /// In ar, this message translates to:
  /// **'تم تطبيق المجلدات الافتراضية لمرجعي. الملفات المدارة والنسخ الاحتياطية السابقة في مواقعها الأصلية.'**
  String get settingsSnackDefaultsApplied;

  /// No description provided for @settingsSnackDefaultsResolutionFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحديد مجلد المستندات. تحقق من صلاحيات النظام.'**
  String get settingsSnackDefaultsResolutionFailed;

  /// No description provided for @settingsSnackDefaultsCreationFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر إنشاء المجلدات الافتراضية. تحقق من المساحة المتاحة وصلاحيات الكتابة.'**
  String get settingsSnackDefaultsCreationFailed;

  /// No description provided for @settingsSnackFallback.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر اعتماد المجلد المحدد. اختر مجلدًا موجودًا وآمنًا.'**
  String get settingsSnackFallback;

  /// No description provided for @settingsManualBackupTitle.
  ///
  /// In ar, this message translates to:
  /// **'النسخ الاحتياطي اليدوي لقاعدة البيانات'**
  String get settingsManualBackupTitle;

  /// No description provided for @settingsManualBackupBody.
  ///
  /// In ar, this message translates to:
  /// **'تُنشئ نسخة احتياطية من سجلات قاعدة بيانات مرجعي (البيانات الوصفية والتصنيفات فقط) في مجلد النسخ الاحتياطي المُهيأ. الملفات القانونية الأصلية وملفات PDF المدارة لا تُدرج في النسخة الاحتياطية ولا تتأثر.'**
  String get settingsManualBackupBody;

  /// No description provided for @settingsManualBackupButton.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء نسخة احتياطية'**
  String get settingsManualBackupButton;

  /// No description provided for @settingsManualBackupDialogTitle.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء نسخة احتياطية من قاعدة البيانات'**
  String get settingsManualBackupDialogTitle;

  /// No description provided for @settingsManualBackupDialogContent.
  ///
  /// In ar, this message translates to:
  /// **'سيتم نسخ قاعدة البيانات المحلية (البيانات الوصفية فقط) إلى مجلد النسخ الاحتياطي المُهيأ.\n\nالملفات القانونية الأصلية وملفات PDF المدارة لا تُدرج في النسخة الاحتياطية ولا يتأثر أي ملف موجود.'**
  String get settingsManualBackupDialogContent;

  /// No description provided for @settingsManualBackupDialogConfirm.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء النسخة'**
  String get settingsManualBackupDialogConfirm;

  /// No description provided for @settingsSnackBackupSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم إنشاء النسخة الاحتياطية بنجاح.'**
  String get settingsSnackBackupSuccess;

  /// No description provided for @settingsSnackBackupNotConfigured.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم تهيئة مجلد النسخ الاحتياطي. اختر مجلدًا من إعدادات المواقع أدناه.'**
  String get settingsSnackBackupNotConfigured;

  /// No description provided for @settingsSnackBackupRootMissing.
  ///
  /// In ar, this message translates to:
  /// **'مجلد النسخ الاحتياطي غير متاح. أعد إنشاءه أو اختر مجلدًا آخر من الإعدادات.'**
  String get settingsSnackBackupRootMissing;

  /// No description provided for @settingsSnackBackupFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر إنشاء النسخة الاحتياطية. تحقق من مساحة القرص وصلاحيات الكتابة.'**
  String get settingsSnackBackupFailed;

  /// No description provided for @settingsStartupRecoveryAttention.
  ///
  /// In ar, this message translates to:
  /// **'توجد ملفات عمل غير مكتملة داخل مجلدات مرجعي تحتاج إلى مراجعة آمنة قبل متابعة النسخ. عدد العناصر: {count}. لم يتم نقل أو حذف أي ملف.'**
  String settingsStartupRecoveryAttention(int count);

  /// No description provided for @settingsRecoveryReviewButton.
  ///
  /// In ar, this message translates to:
  /// **'مراجعة'**
  String get settingsRecoveryReviewButton;

  /// No description provided for @settingsRecoveryReviewDialogTitle.
  ///
  /// In ar, this message translates to:
  /// **'مراجعة ملفات الاسترداد'**
  String get settingsRecoveryReviewDialogTitle;

  /// No description provided for @settingsRecoveryReviewCopyingCount.
  ///
  /// In ar, this message translates to:
  /// **'ملفات نسخ مؤقتة: {count} (مؤهلة للحذف)'**
  String settingsRecoveryReviewCopyingCount(int count);

  /// No description provided for @settingsRecoveryReviewBackupCount.
  ///
  /// In ar, this message translates to:
  /// **'نسخ احتياطية منقوصة: {count} (مؤهلة للحذف)'**
  String settingsRecoveryReviewBackupCount(int count);

  /// No description provided for @settingsRecoveryReviewUnregisteredCount.
  ///
  /// In ar, this message translates to:
  /// **'ملفات PDF غير مسجلة: {count} (تحتاج مراجعة يدوية)'**
  String settingsRecoveryReviewUnregisteredCount(int count);

  /// No description provided for @settingsRecoveryReviewCleanupButton.
  ///
  /// In ar, this message translates to:
  /// **'حذف الملفات المؤهلة'**
  String get settingsRecoveryReviewCleanupButton;

  /// No description provided for @settingsRecoveryReviewConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الحذف الآمن'**
  String get settingsRecoveryReviewConfirmTitle;

  /// No description provided for @settingsRecoveryReviewConfirmContent.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حذف ملفات النسخ المؤقتة وملفات النسخ الاحتياطية المنقوصة فقط.\n\nلن تُمس ملفات PDF المسجلة أو الملفات الأصلية.'**
  String get settingsRecoveryReviewConfirmContent;

  /// No description provided for @settingsRecoveryReviewConfirmAction.
  ///
  /// In ar, this message translates to:
  /// **'حذف الآن'**
  String get settingsRecoveryReviewConfirmAction;

  /// No description provided for @settingsRecoveryReviewLoadFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل تقرير الاسترداد. حاول مرة أخرى.'**
  String get settingsRecoveryReviewLoadFailed;

  /// No description provided for @settingsSnackRecoveryCleaned.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف الملفات المؤهلة بنجاح.'**
  String get settingsSnackRecoveryCleaned;

  /// No description provided for @settingsSnackRecoveryPartialFailure.
  ///
  /// In ar, this message translates to:
  /// **'اكتمل الحذف جزئياً. تعذّر حذف بعض الملفات.'**
  String get settingsSnackRecoveryPartialFailure;

  /// No description provided for @settingsSnackRecoveryFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الحذف. تحقق من صلاحيات الوصول.'**
  String get settingsSnackRecoveryFailed;

  /// No description provided for @settingsSnackRecoveryNothingToClean.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد ملفات مؤهلة للحذف الآمن.'**
  String get settingsSnackRecoveryNothingToClean;

  /// No description provided for @settingsIntegrityTitle.
  ///
  /// In ar, this message translates to:
  /// **'سلامة النسخ المدارة'**
  String get settingsIntegrityTitle;

  /// No description provided for @settingsIntegrityBody.
  ///
  /// In ar, this message translates to:
  /// **'يفحص هذا الاختبار جميع ملفات PDF المسجلة في مكتبة مرجعي ويكتشف الملفات المفقودة أو التي تغيّر محتواها. لا يُعدّل الملفات على القرص ولا يُنشئها.'**
  String get settingsIntegrityBody;

  /// No description provided for @settingsIntegrityButton.
  ///
  /// In ar, this message translates to:
  /// **'فحص النسخ المدارة'**
  String get settingsIntegrityButton;

  /// No description provided for @settingsSnackIntegrityClean.
  ///
  /// In ar, this message translates to:
  /// **'جميع النسخ المدارة سليمة.'**
  String get settingsSnackIntegrityClean;

  /// No description provided for @settingsSnackIntegrityIssues.
  ///
  /// In ar, this message translates to:
  /// **'اكتُشف {count} ملف مشكل في النسخ المدارة.'**
  String settingsSnackIntegrityIssues(int count);

  /// No description provided for @settingsSnackIntegrityFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر فحص النسخ المدارة. حاول مرة أخرى.'**
  String get settingsSnackIntegrityFailed;

  /// No description provided for @duplicatesReviewStatusReviewed.
  ///
  /// In ar, this message translates to:
  /// **'تمت المراجعة'**
  String get duplicatesReviewStatusReviewed;

  /// No description provided for @duplicatesReviewStatusDeferred.
  ///
  /// In ar, this message translates to:
  /// **'مؤجلة'**
  String get duplicatesReviewStatusDeferred;

  /// No description provided for @duplicatesReviewStatusUnreviewed.
  ///
  /// In ar, this message translates to:
  /// **'غير مراجعة'**
  String get duplicatesReviewStatusUnreviewed;

  /// No description provided for @dashboardRelativeDays.
  ///
  /// In ar, this message translates to:
  /// **'{n}ي'**
  String dashboardRelativeDays(int n);

  /// No description provided for @dashboardRelativeHours.
  ///
  /// In ar, this message translates to:
  /// **'{n}س'**
  String dashboardRelativeHours(int n);

  /// No description provided for @dashboardRelativeMinutes.
  ///
  /// In ar, this message translates to:
  /// **'{n}د'**
  String dashboardRelativeMinutes(int n);

  /// No description provided for @dashboardRelativeNow.
  ///
  /// In ar, this message translates to:
  /// **'الآن'**
  String get dashboardRelativeNow;
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
