// lib/features/import/application/import_progress.dart

import 'package:equatable/equatable.dart';

/// The phase an import run is currently in.
enum ImportPhase { validating, scanning, importing, finalizing }

/// Live progress for an import run.
///
/// [processed] counts discovered entries already handled; [discovered] is the
/// total to handle (0 until scanning completes). [currentFileName] is the file
/// being processed during [ImportPhase.importing].
class ImportProgress extends Equatable {
  const ImportProgress({
    required this.phase,
    this.processed = 0,
    this.discovered = 0,
    this.currentFileName,
  });

  final ImportPhase phase;
  final int processed;
  final int discovered;
  final String? currentFileName;

  /// Fraction in [0, 1]; 0 while the total is still unknown.
  double get fraction {
    if (discovered <= 0) return 0;
    final double f = processed / discovered;
    if (f < 0) return 0;
    if (f > 1) return 1;
    return f;
  }

  @override
  List<Object?> get props => [phase, processed, discovered, currentFileName];
}
