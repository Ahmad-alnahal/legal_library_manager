// lib/features/import/domain/services/file_hasher.dart

import '../entities/sha256_result.dart';

/// A cooperative cancellation signal for long-running hashing.
///
/// Persistence- and framework-agnostic so it can be passed from the application
/// layer into the data-layer hasher. The hasher checks [isCancelled] between
/// chunks (a cancellation-friendly boundary for M4.2, no UI implied here).
abstract class HashCancellation {
  bool get isCancelled;
}

/// A simple, always-running cancellation token.
class MutableHashCancellation implements HashCancellation {
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Progress for a single file hash: bytes processed so far out of the total.
class HashProgress {
  const HashProgress({required this.bytesHashed, required this.totalBytes});

  final int bytesHashed;
  final int totalBytes;

  double get fraction => totalBytes == 0 ? 1 : bytesHashed / totalBytes;
}

/// Computes a SHA-256 from a file's bytes using streaming (never loading the
/// whole file into memory) and off the Flutter UI isolate.
///
/// Implementations live in the data layer. A supplied hash is never trusted —
/// the digest is always computed from the bytes.
abstract class FileHasher {
  /// Streams [absolutePath] and returns its lowercase 64-hex SHA-256.
  ///
  /// [cancellation] is polled between chunks; [onProgress] (when given) reports
  /// streaming progress. Both are optional boundaries prepared for M4.2.
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  });
}
