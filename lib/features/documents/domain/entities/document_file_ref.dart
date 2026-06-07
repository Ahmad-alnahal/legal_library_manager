// lib/features/documents/domain/entities/document_file_ref.dart

import 'package:equatable/equatable.dart';

/// Minimal, read-only view of a physical file attached to a document — only the
/// fields needed to evaluate the "acceptable file" approval rule. No paths or
/// filesystem handles are exposed here.
class DocumentFileRef extends Equatable {
  const DocumentFileRef({
    required this.id,
    required this.fileRoleKey,
    required this.fileHealthKey,
  });

  final int id;
  final String fileRoleKey;
  final String fileHealthKey;

  @override
  List<Object?> get props => [id, fileRoleKey, fileHealthKey];
}
