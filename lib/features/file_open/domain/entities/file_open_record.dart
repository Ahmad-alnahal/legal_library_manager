// lib/features/file_open/domain/entities/file_open_record.dart

import 'package:equatable/equatable.dart';

/// Minimal data loaded from [document_files] for the safe-open workflow.
///
/// Contains only the fields required for validation and event recording. No
/// document contents, metadata, or workflow status are included. No Drift or
/// [dart:io] types are referenced.
class FileOpenRecord extends Equatable {
  const FileOpenRecord({
    required this.fileId,
    required this.documentId,
    required this.absolutePath,
    required this.extension,
    required this.fileHealthKey,
  });

  final int fileId;
  final int documentId;
  final String absolutePath;

  /// Normalized lowercase extension including the leading dot, e.g. `.pdf`.
  final String extension;

  /// The file's health status key from [document_files.file_health_status_key].
  final String fileHealthKey;

  @override
  List<Object?> get props => [
    fileId,
    documentId,
    absolutePath,
    extension,
    fileHealthKey,
  ];
}
