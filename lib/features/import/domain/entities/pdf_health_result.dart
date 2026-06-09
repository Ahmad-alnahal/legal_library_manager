// lib/features/import/domain/entities/pdf_health_result.dart

import 'package:equatable/equatable.dart';

/// Conservative PDF-health outcomes, matching `file_health_statuses` keys.
enum PdfHealthStatus {
  healthy,
  corrupted,
  unreadable,
  missing,
  unknown;

  /// The stable database key for this status.
  String get key => name;
}

/// The result of a conservative PDF health inspection.
///
/// [pageCount] is populated only when it can be derived safely without a heavy
/// or licensed PDF dependency; otherwise it is `null`. [sizeBytes] is `null`
/// when the size could not be read.
class PdfHealthResult extends Equatable {
  const PdfHealthResult({required this.status, this.sizeBytes, this.pageCount});

  final PdfHealthStatus status;
  final int? sizeBytes;
  final int? pageCount;

  @override
  List<Object?> get props => [status, sizeBytes, pageCount];
}
