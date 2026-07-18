// lib/features/export/domain/entities/export_keywords_result.dart

import 'package:equatable/equatable.dart';

/// One normalized keyword used by the exported document set.
class ExportKeywordEntry extends Equatable {
  const ExportKeywordEntry({required this.keywordText});

  final String keywordText;

  @override
  List<Object?> get props => [keywordText];
}

/// One document-to-keyword link, identified by document code (never the
/// integer document id).
class ExportDocumentKeywordEntry extends Equatable {
  const ExportDocumentKeywordEntry({
    required this.documentCode,
    required this.keywordText,
  });

  final String documentCode;
  final String keywordText;

  @override
  List<Object?> get props => [documentCode, keywordText];
}

/// Keywords and document-keyword links for a set of exported documents.
class ExportKeywordsResult extends Equatable {
  const ExportKeywordsResult({
    required this.keywords,
    required this.documentKeywords,
  });

  final List<ExportKeywordEntry> keywords;
  final List<ExportDocumentKeywordEntry> documentKeywords;

  @override
  List<Object?> get props => [keywords, documentKeywords];
}
