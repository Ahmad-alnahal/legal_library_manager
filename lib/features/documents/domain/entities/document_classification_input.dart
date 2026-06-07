// lib/features/documents/domain/entities/document_classification_input.dart

import 'package:equatable/equatable.dart';

/// A single legal classification: a main category and an optional subcategory.
///
/// Role (primary vs additional) is determined by where the classification is
/// placed in the draft input, not stored on this value object.
class DocumentClassificationInput extends Equatable {
  const DocumentClassificationInput({
    required this.mainCategoryId,
    this.subCategoryId,
  });

  final int mainCategoryId;
  final int? subCategoryId;

  @override
  List<Object?> get props => [mainCategoryId, subCategoryId];
}
