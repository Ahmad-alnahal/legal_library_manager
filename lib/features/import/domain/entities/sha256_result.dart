// lib/features/import/domain/entities/sha256_result.dart

import 'package:equatable/equatable.dart';

import 'import_error.dart';

/// The outcome of hashing a file's bytes.
///
/// On success [hash] is a lowercase 64-character hexadecimal SHA-256 value
/// computed from the file's bytes (never a supplied/untrusted hash). On failure
/// [error] explains why, safely.
class Sha256Result extends Equatable {
  const Sha256Result._({this.hash, this.error});

  /// A successful result wrapping a validated lowercase 64-hex digest.
  factory Sha256Result.success(String hash) {
    assert(
      _isLowercaseHex64(hash),
      'SHA-256 must be lowercase 64-char hexadecimal',
    );
    return Sha256Result._(hash: hash);
  }

  /// A failed result carrying a safe error.
  factory Sha256Result.failure(ImportError error) =>
      Sha256Result._(error: error);

  /// Lowercase 64-character hexadecimal digest, or `null` on failure.
  final String? hash;

  /// The safe failure, or `null` on success.
  final ImportError? error;

  bool get isSuccess => hash != null;

  static bool _isLowercaseHex64(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  @override
  List<Object?> get props => [hash, error];
}
