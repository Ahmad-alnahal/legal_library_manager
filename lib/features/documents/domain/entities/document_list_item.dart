import 'package:equatable/equatable.dart';

class DocumentListItem extends Equatable {
  const DocumentListItem({
    required this.id,
    required this.workflowStatusKey,
    required this.trustLevelKey,
    required this.metadataQualityKey,
    required this.fileCount,
    required this.hasDuplicate,
    required this.hasCorruptedFile,
    required this.hasUnreadableFile,
    required this.updatedAt,
    this.documentCode,
    this.title,
    this.sourceFileName,
    this.documentTypeId,
    this.documentTypeNameAr,
    this.primaryMainCategoryId,
    this.primaryMainCategoryNameAr,
    this.primarySubCategoryId,
    this.primarySubCategoryNameAr,
    this.languageKey,
    this.countryKey,
    this.publicationYear,
  });

  final int id;
  final String? documentCode;
  final String? title;
  final String? sourceFileName;
  final int? documentTypeId;
  final String? documentTypeNameAr;
  final int? primaryMainCategoryId;
  final String? primaryMainCategoryNameAr;
  final int? primarySubCategoryId;
  final String? primarySubCategoryNameAr;
  final String? languageKey;
  final String? countryKey;
  final int? publicationYear;
  final String workflowStatusKey;
  final String trustLevelKey;
  final String metadataQualityKey;
  final int fileCount;
  final bool hasDuplicate;
  final bool hasCorruptedFile;
  final bool hasUnreadableFile;
  final String updatedAt;

  @override
  List<Object?> get props => [
    id,
    documentCode,
    title,
    sourceFileName,
    documentTypeId,
    documentTypeNameAr,
    primaryMainCategoryId,
    primaryMainCategoryNameAr,
    primarySubCategoryId,
    primarySubCategoryNameAr,
    languageKey,
    countryKey,
    publicationYear,
    workflowStatusKey,
    trustLevelKey,
    metadataQualityKey,
    fileCount,
    hasDuplicate,
    hasCorruptedFile,
    hasUnreadableFile,
    updatedAt,
  ];
}

class DocumentListPage extends Equatable {
  const DocumentListPage({
    required this.items,
    required this.totalCount,
    required this.offset,
    required this.limit,
  });

  final List<DocumentListItem> items;
  final int totalCount;
  final int offset;
  final int limit;

  bool get hasMore => offset + items.length < totalCount;

  @override
  List<Object?> get props => [items, totalCount, offset, limit];
}

class DocumentSourceFileItem extends Equatable {
  const DocumentSourceFileItem({
    required this.id,
    required this.fileName,
    required this.absolutePath,
    required this.fileRoleKey,
    required this.fileHealthKey,
    required this.fileSizeBytes,
    required this.isReadOnlySource,
  });

  final int id;
  final String fileName;
  final String absolutePath;
  final String fileRoleKey;
  final String fileHealthKey;
  final int fileSizeBytes;
  final bool isReadOnlySource;

  @override
  List<Object?> get props => [
    id,
    fileName,
    absolutePath,
    fileRoleKey,
    fileHealthKey,
    fileSizeBytes,
    isReadOnlySource,
  ];
}
