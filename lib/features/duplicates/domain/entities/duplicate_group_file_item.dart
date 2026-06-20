// lib/features/duplicates/domain/entities/duplicate_group_file_item.dart

import 'package:equatable/equatable.dart';

/// A single physical-file member of a duplicate group — read-only.
class DuplicateGroupFileItem extends Equatable {
  const DuplicateGroupFileItem({
    required this.fileId,
    required this.documentId,
    this.documentCode,
    this.documentTitle,
    required this.fileName,
    required this.absolutePath,
    required this.fileRoleKey,
    required this.fileHealthKey,
    required this.fileSizeBytes,
    required this.workflowStatusKey,
    required this.isHiddenFromSearch,
    required this.isPreferred,
    required this.addedAt,
  });

  final int fileId;
  final int documentId;
  final String? documentCode;

  /// The document title, or null when metadata has not been filled in yet.
  final String? documentTitle;
  final String fileName;
  final String absolutePath;
  final String fileRoleKey;
  final String fileHealthKey;
  final int fileSizeBytes;
  final String workflowStatusKey;
  final bool isHiddenFromSearch;
  final bool isPreferred;
  final String addedAt;

  /// Best available display name: title → fileName → documentCode → fallback.
  String get displayName {
    final t = documentTitle;
    if (t != null && t.isNotEmpty) return t;
    if (fileName.isNotEmpty) return fileName;
    final c = documentCode;
    if (c != null && c.isNotEmpty) return c;
    return 'مستند بلا عنوان';
  }

  @override
  List<Object?> get props => [
    fileId,
    documentId,
    documentCode,
    documentTitle,
    fileName,
    absolutePath,
    fileRoleKey,
    fileHealthKey,
    fileSizeBytes,
    workflowStatusKey,
    isHiddenFromSearch,
    isPreferred,
    addedAt,
  ];
}
