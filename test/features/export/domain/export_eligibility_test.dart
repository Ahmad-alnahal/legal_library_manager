// test/features/export/domain/export_eligibility_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_eligibility_input.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_eligibility_result.dart';
import 'package:legal_library_manager/features/export/domain/export_eligibility.dart';

void main() {
  ExportEligibilityInput eligible({
    String workflowStatusKey = 'copied_to_library',
    bool hasHealthyManagedCopy = true,
    int? primaryMainCategoryId = 1,
    bool? primaryMainCategoryActive = true,
    int? primarySubCategoryId,
    bool? primarySubCategoryActive,
    String metadataQualityKey = 'high',
    String? usageRightsKey = 'open_access',
  }) => ExportEligibilityInput(
    workflowStatusKey: workflowStatusKey,
    hasHealthyManagedCopy: hasHealthyManagedCopy,
    primaryMainCategoryId: primaryMainCategoryId,
    primaryMainCategoryActive: primaryMainCategoryActive,
    primarySubCategoryId: primarySubCategoryId,
    primarySubCategoryActive: primarySubCategoryActive,
    metadataQualityKey: metadataQualityKey,
    usageRightsKey: usageRightsKey,
  );

  test('a fully valid document is eligible', () {
    final result = checkExportEligibility(eligible());
    expect(result, isA<ExportEligible>());
  });

  test('wrong workflow status is ineligible', () {
    final result = checkExportEligibility(
      eligible(workflowStatusKey: 'classified'),
    );
    expect(result, isA<ExportIneligible>());
    expect((result as ExportIneligible).reasons, [
      'Document must be copied_to_library before it can be marked '
          'ready_for_export.',
    ]);
  });

  test('archived document reports the archived reason only', () {
    final result = checkExportEligibility(
      eligible(workflowStatusKey: 'archived'),
    );
    expect(result, isA<ExportIneligible>());
    expect((result as ExportIneligible).reasons, ['Document is archived.']);
  });

  test('missing healthy managed copy is ineligible', () {
    final result = checkExportEligibility(
      eligible(hasHealthyManagedCopy: false),
    );
    expect((result as ExportIneligible).reasons, [
      'Document has no healthy managed-copy file.',
    ]);
  });

  test('missing primary main category is ineligible', () {
    final result = checkExportEligibility(
      eligible(primaryMainCategoryId: null, primaryMainCategoryActive: null),
    );
    expect((result as ExportIneligible).reasons, [
      'Document has no active primary classification.',
    ]);
  });

  test('inactive primary main category is ineligible', () {
    final result = checkExportEligibility(
      eligible(primaryMainCategoryActive: false),
    );
    expect((result as ExportIneligible).reasons, [
      'Document has no active primary classification.',
    ]);
  });

  test('inactive primary subcategory is ineligible', () {
    final result = checkExportEligibility(
      eligible(primarySubCategoryId: 2, primarySubCategoryActive: false),
    );
    expect((result as ExportIneligible).reasons, [
      'Document primary subcategory is not active.',
    ]);
  });

  test('active primary subcategory does not block eligibility', () {
    final result = checkExportEligibility(
      eligible(primarySubCategoryId: 2, primarySubCategoryActive: true),
    );
    expect(result, isA<ExportEligible>());
  });

  test('metadata quality below high/verified is ineligible', () {
    for (final quality in ['low', 'medium']) {
      final result = checkExportEligibility(
        eligible(metadataQualityKey: quality),
      );
      expect((result as ExportIneligible).reasons, [
        'Metadata quality must be high or verified.',
      ]);
    }
  });

  test('verified metadata quality is accepted', () {
    final result = checkExportEligibility(
      eligible(metadataQualityKey: 'verified'),
    );
    expect(result, isA<ExportEligible>());
  });

  test('null usage rights is ineligible', () {
    final result = checkExportEligibility(eligible(usageRightsKey: null));
    expect((result as ExportIneligible).reasons, [
      'Usage rights must be explicitly reviewed.',
    ]);
  });

  test('unknown usage rights is ineligible', () {
    final result = checkExportEligibility(eligible(usageRightsKey: 'unknown'));
    expect((result as ExportIneligible).reasons, [
      'Usage rights must be explicitly reviewed.',
    ]);
  });

  test('personal_use_only and permission_required usage rights are eligible '
      '(local export allowed but must be flagged elsewhere)', () {
    for (final rights in ['personal_use_only', 'permission_required']) {
      final result = checkExportEligibility(eligible(usageRightsKey: rights));
      expect(result, isA<ExportEligible>());
    }
  });

  test('multiple violated rules all appear in reasons', () {
    final result = checkExportEligibility(
      eligible(
        workflowStatusKey: 'classified',
        hasHealthyManagedCopy: false,
        metadataQualityKey: 'low',
        usageRightsKey: 'unknown',
      ),
    );
    expect((result as ExportIneligible).reasons, [
      'Document must be copied_to_library before it can be marked '
          'ready_for_export.',
      'Document has no healthy managed-copy file.',
      'Metadata quality must be high or verified.',
      'Usage rights must be explicitly reviewed.',
    ]);
  });
}
