// lib/features/documents/domain/validation/reference_validator.dart

import '../../../../core/validation/validation_result.dart';
import '../../../reference/domain/repositories/reference_repository.dart';
import '../entities/document_classification_input.dart';
import '../entities/document_common_metadata.dart';
import '../entities/document_type_details.dart';

/// A snapshot of currently-active reference data, loaded once so reference and
/// cross-table checks can run synchronously.
class ActiveReferenceData {
  ActiveReferenceData({
    required this.documentTypeKeyById,
    required this.mainCategoryIds,
    required this.mainIdBySubId,
    required this.activeSubCountByMainId,
    required this.languageKeys,
    required this.countryKeys,
    required this.trustLevelKeys,
    required this.usageRightsKeys,
    required this.metadataQualityKeys,
  });

  final Map<int, String> documentTypeKeyById;
  final Set<int> mainCategoryIds;
  final Map<int, int> mainIdBySubId;
  final Map<int, int> activeSubCountByMainId;
  final Set<String> languageKeys;
  final Set<String> countryKeys;
  final Set<String> trustLevelKeys;
  final Set<String> usageRightsKeys;
  final Set<String> metadataQualityKeys;

  /// True when the given main category currently has at least one active
  /// subcategory (used by the "subcategory required" approval rule).
  bool mainHasActiveSubcategories(int mainCategoryId) =>
      (activeSubCountByMainId[mainCategoryId] ?? 0) > 0;

  static Future<ActiveReferenceData> load(ReferenceRepository refs) async {
    final types = await refs.getDocumentTypes();
    final mains = await refs.getMainCategories();
    final subs = await refs.getSubCategories();
    final languages = await refs.getLanguages();
    final countries = await refs.getCountries();
    final trust = await refs.getTrustLevels();
    final usage = await refs.getUsageRights();
    final quality = await refs.getMetadataQualities();

    final Map<int, int> mainIdBySubId = {};
    final Map<int, int> activeSubCount = {};
    for (final s in subs) {
      mainIdBySubId[s.id] = s.mainCategoryId;
      activeSubCount[s.mainCategoryId] =
          (activeSubCount[s.mainCategoryId] ?? 0) + 1;
    }

    return ActiveReferenceData(
      documentTypeKeyById: {for (final t in types) t.id: t.key},
      mainCategoryIds: {for (final m in mains) m.id},
      mainIdBySubId: mainIdBySubId,
      activeSubCountByMainId: activeSubCount,
      languageKeys: {for (final l in languages) l.key},
      countryKeys: {for (final c in countries) c.key},
      trustLevelKeys: {for (final t in trust) t.key},
      usageRightsKeys: {for (final u in usage) u.key},
      metadataQualityKeys: {for (final q in quality) q.key},
    );
  }
}

/// Pure reference/cross-table checks against an [ActiveReferenceData] snapshot.
/// Only set values are validated (drafts may omit fields); these checks never
/// require fields to be present.
abstract final class ReferenceChecks {
  /// Validates that any set common reference is active.
  static void commonReferences(
    DocumentCommonMetadata c,
    ActiveReferenceData data,
    ValidationErrorBuilder errors,
  ) {
    if (c.documentTypeId != null &&
        !data.documentTypeKeyById.containsKey(c.documentTypeId)) {
      errors.add(
        'documentTypeId',
        'invalid_reference',
        'Document type is not an active reference.',
      );
    }
    _key(errors, 'languageKey', c.languageKey, data.languageKeys);
    _key(errors, 'countryKey', c.countryKey, data.countryKeys);
    _key(errors, 'trustLevelKey', c.trustLevelKey, data.trustLevelKeys);
    _key(errors, 'usageRightsKey', c.usageRightsKey, data.usageRightsKeys);
    _key(
      errors,
      'metadataQualityKey',
      c.metadataQualityKey,
      data.metadataQualityKeys,
    );
  }

  /// Validates that each classification's main category is active and any
  /// subcategory is active and belongs to that main category.
  static void classifications(
    DocumentClassificationInput? primary,
    List<DocumentClassificationInput> additionals,
    ActiveReferenceData data,
    ValidationErrorBuilder errors,
  ) {
    void check(DocumentClassificationInput c, String field) {
      if (!data.mainCategoryIds.contains(c.mainCategoryId)) {
        errors.add(
          field,
          'invalid_reference',
          'Main category ${c.mainCategoryId} is not an active reference.',
        );
      }
      final int? subId = c.subCategoryId;
      if (subId != null) {
        final int? owner = data.mainIdBySubId[subId];
        if (owner == null) {
          errors.add(
            field,
            'invalid_reference',
            'Subcategory $subId is not an active reference.',
          );
        } else if (owner != c.mainCategoryId) {
          errors.add(
            field,
            'subcategory_mismatch',
            'Subcategory $subId does not belong to main ${c.mainCategoryId}.',
          );
        }
      }
    }

    if (primary != null) check(primary, 'primaryClassification');
    for (int i = 0; i < additionals.length; i++) {
      check(additionals[i], 'additionalClassifications[$i]');
    }
  }

  /// Validates that a supplied detail object matches the selected document type
  /// (and therefore that `other`/unset types carry no detail row).
  static void detailMatchesType(
    int? documentTypeId,
    DocumentTypeDetails? details,
    ActiveReferenceData data,
    ValidationErrorBuilder errors,
  ) {
    if (details == null) return;
    final String? typeKey = documentTypeId == null
        ? null
        : data.documentTypeKeyById[documentTypeId];
    if (typeKey == null || details.documentTypeKey != typeKey) {
      errors.add(
        'details',
        'detail_type_mismatch',
        'Detail of type "${details.documentTypeKey}" does not match the '
            'selected document type.',
      );
    }
  }

  static void _key(
    ValidationErrorBuilder errors,
    String field,
    String? value,
    Set<String> active,
  ) {
    if (value != null && !active.contains(value)) {
      errors.add(field, 'invalid_reference', '"$value" is not active.');
    }
  }
}
