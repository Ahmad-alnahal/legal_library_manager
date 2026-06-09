// lib/features/import/domain/services/pdf_health_inspector.dart

import '../entities/pdf_health_result.dart';

/// Conservatively inspects a PDF's health without modifying it and without a
/// heavy or licensed PDF dependency. Implementations live in the data layer.
///
/// M4.2 integration requirement: inspection performs synchronous file reads and
/// MUST be invoked off the Flutter UI isolate (e.g. via `Isolate.run`, or inside
/// the same background isolate used for scanning/hashing) so PDF inspection of
/// large files never blocks the UI. Inputs/outputs are sendable across isolates.
abstract class PdfHealthInspector {
  /// Inspects [absolutePath]: existence, regular-file status, readable
  /// non-negative size, `.pdf` extension, and a plausible header signature.
  /// Records [PdfHealthResult.pageCount] only when safely available.
  Future<PdfHealthResult> inspect(String absolutePath);
}
