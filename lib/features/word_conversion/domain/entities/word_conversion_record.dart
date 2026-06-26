// lib/features/word_conversion/domain/entities/word_conversion_record.dart

import 'package:equatable/equatable.dart';

/// Safe projection of a `file_conversions` row.
///
/// Returned by [WordConversionRepository.findActiveConversion]. No Drift types
/// leak into this class.
class WordConversionRecord extends Equatable {
  const WordConversionRecord({
    required this.conversionId,
    required this.statusKey,
  });

  final int conversionId;

  /// Conversion status key from the `file_conversions.status_key` column.
  final String statusKey;

  @override
  List<Object?> get props => [conversionId, statusKey];
}
