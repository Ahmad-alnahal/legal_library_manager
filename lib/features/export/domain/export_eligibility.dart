// lib/features/export/domain/export_eligibility.dart

import '../../../core/constants/domain_keys.dart';
import 'entities/export_eligibility_input.dart';
import 'entities/export_eligibility_result.dart';

/// Pure export-eligibility check (workflow_and_validation_spec.md §10).
///
/// `copied_to_library -> ready_for_export` preconditions:
/// - managed copy exists and hash verification passes (a healthy
///   `managed_copy` file, checked upstream and summarized in
///   [ExportEligibilityInput.hasHealthyManagedCopy]);
/// - classification remains valid (an active primary main category, and an
///   active primary subcategory when one is set);
/// - metadata quality is not `low`;
/// - usage rights is explicitly reviewed and not `unknown`;
/// - the document is not archived.
///
/// No document-state I/O happens here; the repository loads only the fields
/// this function needs.
ExportEligibilityResult checkExportEligibility(ExportEligibilityInput input) {
  final List<String> reasons = [];

  if (input.workflowStatusKey == WorkflowStatusKey.archived) {
    reasons.add('المستند محفوظ في الأرشيف.');
  } else if (input.workflowStatusKey != WorkflowStatusKey.copiedToLibrary) {
    reasons.add(
      'يجب نسخ المستند إلى المكتبة أولاً قبل تعيينه جاهزاً للتصدير.',
    );
  }

  if (!input.hasHealthyManagedCopy) {
    reasons.add('لا توجد نسخة مُدارة سليمة للمستند.');
  }

  if (input.primaryMainCategoryId == null ||
      input.primaryMainCategoryActive != true) {
    reasons.add('المستند لا يحمل تصنيفاً رئيسياً نشطاً.');
  } else if (input.primarySubCategoryId != null &&
      input.primarySubCategoryActive != true) {
    reasons.add('التصنيف الفرعي الرئيسي للمستند غير نشط.');
  }

  if (input.metadataQualityKey == MetadataQualityKey.low) {
    reasons.add(
      'جودة البيانات الوصفية منخفضة جداً — يُشترط مستوى متوسط على الأقل.',
    );
  }

  if (input.usageRightsKey == null ||
      input.usageRightsKey == UsageRightsKey.unknown) {
    reasons.add('يجب تحديد حقوق الاستخدام قبل التصدير.');
  }

  if (reasons.isEmpty) return const ExportEligible();
  return ExportIneligible(reasons);
}
