// lib/features/managed_copy/data/services/default_operation_id_generator.dart

import 'dart:math';

import '../../domain/services/operation_id_generator.dart';

/// Production [OperationIdGenerator].
///
/// Combines the UTC millisecond timestamp with a cryptographically random
/// 24-bit hex suffix, making collisions effectively impossible even when
/// multiple operations start within the same millisecond.
///
/// Output format: `copy_<ms>_<6-hex-chars>` — filename-safe on Windows.
class DefaultOperationIdGenerator implements OperationIdGenerator {
  const DefaultOperationIdGenerator();

  @override
  String generate(DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    final suffix = Random.secure()
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return 'copy_${ms}_$suffix';
  }
}
