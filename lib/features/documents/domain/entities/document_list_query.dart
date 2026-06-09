import 'package:equatable/equatable.dart';

enum DocumentListSort {
  updatedNewest,
  updatedOldest,
  titleAscending,
  titleDescending,
  publicationYearNewest,
  publicationYearOldest,
}

enum DuplicateFilter { any, duplicatesOnly, withoutDuplicates }

class DocumentListFilters extends Equatable {
  const DocumentListFilters({
    this.search,
    this.workflowStatusKey,
    this.documentTypeId,
    this.mainCategoryId,
    this.subCategoryId,
    this.countryKey,
    this.languageKey,
    this.trustLevelKey,
    this.fileHealthKey,
    this.duplicateFilter = DuplicateFilter.any,
  });

  final String? search;
  final String? workflowStatusKey;
  final int? documentTypeId;
  final int? mainCategoryId;
  final int? subCategoryId;
  final String? countryKey;
  final String? languageKey;
  final String? trustLevelKey;
  final String? fileHealthKey;
  final DuplicateFilter duplicateFilter;

  DocumentListFilters copyWith({
    String? search,
    bool clearSearch = false,
    String? workflowStatusKey,
    bool clearWorkflowStatus = false,
    int? documentTypeId,
    bool clearDocumentType = false,
    int? mainCategoryId,
    bool clearMainCategory = false,
    int? subCategoryId,
    bool clearSubCategory = false,
    String? countryKey,
    bool clearCountry = false,
    String? languageKey,
    bool clearLanguage = false,
    String? trustLevelKey,
    bool clearTrustLevel = false,
    String? fileHealthKey,
    bool clearFileHealth = false,
    DuplicateFilter? duplicateFilter,
  }) {
    return DocumentListFilters(
      search: clearSearch ? null : search ?? this.search,
      workflowStatusKey: clearWorkflowStatus
          ? null
          : workflowStatusKey ?? this.workflowStatusKey,
      documentTypeId: clearDocumentType
          ? null
          : documentTypeId ?? this.documentTypeId,
      mainCategoryId: clearMainCategory
          ? null
          : mainCategoryId ?? this.mainCategoryId,
      subCategoryId: clearSubCategory
          ? null
          : subCategoryId ?? this.subCategoryId,
      countryKey: clearCountry ? null : countryKey ?? this.countryKey,
      languageKey: clearLanguage ? null : languageKey ?? this.languageKey,
      trustLevelKey: clearTrustLevel
          ? null
          : trustLevelKey ?? this.trustLevelKey,
      fileHealthKey: clearFileHealth
          ? null
          : fileHealthKey ?? this.fileHealthKey,
      duplicateFilter: duplicateFilter ?? this.duplicateFilter,
    );
  }

  DocumentListFilters normalized() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    return DocumentListFilters(
      search: clean(search),
      workflowStatusKey: clean(workflowStatusKey),
      documentTypeId: documentTypeId,
      mainCategoryId: mainCategoryId,
      subCategoryId: subCategoryId,
      countryKey: clean(countryKey),
      languageKey: clean(languageKey),
      trustLevelKey: clean(trustLevelKey),
      fileHealthKey: clean(fileHealthKey),
      duplicateFilter: duplicateFilter,
    );
  }

  @override
  List<Object?> get props => [
    search,
    workflowStatusKey,
    documentTypeId,
    mainCategoryId,
    subCategoryId,
    countryKey,
    languageKey,
    trustLevelKey,
    fileHealthKey,
    duplicateFilter,
  ];
}

class DocumentListQuery extends Equatable {
  const DocumentListQuery({
    this.filters = const DocumentListFilters(),
    this.sort = DocumentListSort.updatedNewest,
    this.offset = 0,
    this.limit = 50,
  });

  final DocumentListFilters filters;
  final DocumentListSort sort;
  final int offset;
  final int limit;

  DocumentListQuery copyWith({
    DocumentListFilters? filters,
    DocumentListSort? sort,
    int? offset,
    int? limit,
  }) {
    return DocumentListQuery(
      filters: filters ?? this.filters,
      sort: sort ?? this.sort,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
    );
  }

  @override
  List<Object?> get props => [filters, sort, offset, limit];
}
