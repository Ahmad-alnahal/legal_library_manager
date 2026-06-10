// lib/features/categories/presentation/widgets/category_labels.dart

import '../../../../core/validation/validation_error.dart';

/// Arabic success message for a completed category operation key.
String categoryOpSuccessMessage(String? key) => switch (key) {
  'main_added' => 'تمت إضافة الفئة الرئيسية.',
  'main_updated' => 'تم تحديث الفئة الرئيسية.',
  'main_activated' => 'تم تفعيل الفئة الرئيسية.',
  'main_deactivated' => 'تم إلغاء تفعيل الفئة الرئيسية.',
  'sub_added' => 'تمت إضافة الفئة الفرعية.',
  'sub_updated' => 'تم تحديث الفئة الفرعية.',
  'sub_activated' => 'تم تفعيل الفئة الفرعية.',
  'sub_deactivated' => 'تم إلغاء تفعيل الفئة الفرعية.',
  'sub_moved' => 'تم نقل الفئة الفرعية إلى الفئة الرئيسية الجديدة.',
  _ => 'تم تنفيذ العملية.',
};

/// Maps a structured category [ValidationError] to a clear Arabic message.
/// Never exposes internal codes or stack traces.
String categoryErrorMessage(ValidationError error) {
  switch (error.code) {
    case 'in_use':
      return 'لا يمكن نقل هذه الفئة الفرعية لأنها مستخدمة في تصنيف مستندات قائمة.';
    case 'duplicate':
      return error.field == 'nameEn'
          ? 'يوجد بالفعل تصنيف بنفس الاسم الإنجليزي.'
          : 'يوجد بالفعل تصنيف بنفس الاسم العربي.';
    case 'required':
      return error.field == 'nameEn'
          ? 'الاسم الإنجليزي مطلوب.'
          : 'الاسم العربي مطلوب.';
    case 'too_long':
      return 'الاسم يتجاوز الحد المسموح من الأحرف.';
    case 'invalid_chars':
      return error.field == 'nameEn'
          ? 'يحتوي الاسم الإنجليزي على رموز تحكم أو محارف غير مرئية غير مسموح بها.'
          : 'يحتوي الاسم العربي على رموز تحكم أو محارف غير مرئية غير مسموح بها.';
    case 'arabic_script_required':
      return categoryArabicScriptRequiredMessage;
    case 'arabic_script_only':
      return categoryArabicScriptOnlyMessage;
    case 'latin_script_required':
      return categoryLatinScriptRequiredMessage;
    case 'latin_script_only':
      return categoryLatinScriptOnlyMessage;
    case 'inactive':
      return 'يجب اختيار فئة رئيسية مفعّلة.';
  }
  return 'تعذّر إكمال العملية.';
}

/// Arabic message: the Arabic-name field has no Arabic letter.
const String categoryArabicScriptRequiredMessage =
    'يجب أن يحتوي الاسم العربي على حروف عربية.';

/// Arabic message: the Arabic-name field contains Latin letters.
const String categoryArabicScriptOnlyMessage =
    'يجب أن يحتوي الاسم العربي على حروف عربية فقط دون حروف لاتينية.';

/// Arabic message: the English-name field has no Latin letter.
const String categoryLatinScriptRequiredMessage =
    'يجب أن يحتوي الاسم الإنجليزي على حروف لاتينية.';

/// Arabic message: the English-name field contains Arabic letters.
const String categoryLatinScriptOnlyMessage =
    'يجب أن يحتوي الاسم الإنجليزي على حروف لاتينية فقط دون حروف عربية.';

/// Generic Arabic message for an unexpected operation error.
const String categoryUnexpectedErrorMessage =
    'تعذّر إكمال العملية. لم تتأثر أي ملفات أصلية.';
