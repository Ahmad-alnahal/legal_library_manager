// lib/features/import/domain/services/pdf_scanner.dart

import '../entities/import_request.dart';
import '../entities/pdf_candidate.dart';

/// Discovers `.pdf` files under a (validated) source folder.
///
/// Implementations live in the data layer. They scan recursively or not, return
/// candidates in deterministic order, include regular files only, match `.pdf`
/// case-insensitively, never descend into protected roots, and continue past
/// individual entry failures.
///
/// M4.2 integration requirement: scanning performs synchronous filesystem
/// enumeration and MUST be invoked off the Flutter UI isolate (e.g. via
/// `Isolate.run(() => scanner.scan(request))`) so large folders never block the
/// UI. Inputs/outputs are sendable across isolates by design.
abstract class PdfScanner {
  /// Scans according to [request]. The caller is expected to have validated the
  /// source folder first.
  Future<PdfScanResult> scan(ImportRequest request);
}
