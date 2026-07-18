// lib/features/export/domain/entities/export_legislation_details.dart

import 'package:equatable/equatable.dart';

/// Website-safe legislation-specific details for one exported document.
class ExportLegislationDetails extends Equatable {
  const ExportLegislationDetails({
    required this.legislationNumber,
    required this.legislationYear,
    required this.effectiveDate,
    required this.repealDate,
    required this.effectiveStatusKey,
    required this.legislationTypeKey,
    required this.legislationTypeOther,
  });

  final String? legislationNumber;
  final String? legislationYear;
  final String? effectiveDate;
  final String? repealDate;
  final String? effectiveStatusKey;
  final String? legislationTypeKey;
  final String? legislationTypeOther;

  @override
  List<Object?> get props => [
    legislationNumber,
    legislationYear,
    effectiveDate,
    repealDate,
    effectiveStatusKey,
    legislationTypeKey,
    legislationTypeOther,
  ];
}
