// lib/features/reference/domain/entities/reference_item.dart

import 'package:equatable/equatable.dart';

/// A generic bilingual reference item keyed by a stable English `snake_case`
/// key (used for languages, countries, trust levels, usage rights, metadata
/// qualities, workflow statuses, file roles, and file-health statuses).
class ReferenceItem extends Equatable {
  const ReferenceItem({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
  });

  /// Stable English `snake_case` (or lowercase code) primary key.
  final String key;

  /// Arabic display name.
  final String nameAr;

  /// English display name.
  final String nameEn;

  /// Deterministic display ordering.
  final int sortOrder;

  @override
  List<Object?> get props => [key, nameAr, nameEn, sortOrder];
}
