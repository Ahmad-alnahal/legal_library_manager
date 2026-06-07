// lib/features/reference/domain/entities/document_type_ref.dart

import 'package:equatable/equatable.dart';

/// A document type reference entry (integer id + stable key + bilingual names).
class DocumentTypeRef extends Equatable {
  const DocumentTypeRef({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
  });

  final int id;
  final String key;
  final String nameAr;
  final String nameEn;
  final int sortOrder;

  @override
  List<Object?> get props => [id, key, nameAr, nameEn, sortOrder];
}
