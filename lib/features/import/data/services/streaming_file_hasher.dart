// lib/features/import/data/services/streaming_file_hasher.dart

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../../domain/entities/import_error.dart';
import '../../domain/entities/sha256_result.dart';
import '../../domain/services/file_hasher.dart';

/// Streaming [FileHasher] backed by `package:crypto`, executing every hash in a
/// dedicated worker isolate — including the progress/cancellation path.
///
/// The worker reads the file in bounded chunks and feeds a chunked SHA-256
/// conversion, so the whole file is never held in memory. Progress is streamed
/// back to the caller; cancellation requests are sent into the worker, which
/// stops between bounded chunks. No chunk hashing ever runs on the caller/UI
/// isolate. The file is only ever opened for reading; a supplied hash is never
/// trusted. Failures are returned as safe [Sha256Result.failure] values.
class StreamingFileHasher implements FileHasher {
  const StreamingFileHasher({
    this.chunkSize = _defaultChunkSize,
    this.debugCrashWorker = false,
  });

  static const int _defaultChunkSize = 1 << 20; // 1 MiB.

  /// Bytes read per chunk inside the worker. Kept small relative to file size so
  /// memory stays bounded regardless of PDF size.
  final int chunkSize;

  /// Test-only seam: when true the worker throws an uncaught error right after
  /// handshake, exercising the unexpected-worker-error/exit recovery path.
  @visibleForTesting
  final bool debugCrashWorker;

  /// Cancellation poll interval — the caller isolate forwards a late
  /// cancellation to the worker within this bound (worker still only stops
  /// between chunks).
  static const Duration _pollInterval = Duration(milliseconds: 25);

  /// The service id of the most recent worker isolate. Test-only seam used to
  /// prove hashing runs off the caller isolate.
  @visibleForTesting
  static String? lastWorkerIsolateId;

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    final ReceivePort receive = ReceivePort();
    final Completer<Sha256Result> completer = Completer<Sha256Result>();

    final _HashRequest request = _HashRequest(
      sendPort: receive.sendPort,
      path: absolutePath,
      chunkSize: chunkSize,
      wantsProgress: onProgress != null,
      startCancelled: cancellation?.isCancelled ?? false,
      crashAfterHandshake: debugCrashWorker,
    );

    SendPort? control;
    Timer? pollTimer;
    Isolate? isolate;

    void completeFailure(String message) {
      if (!completer.isCompleted) {
        completer.complete(
          Sha256Result.failure(
            ImportError(
              code: ImportErrorCode.hashFailed,
              path: absolutePath,
              message: message,
            ),
          ),
        );
      }
    }

    final StreamSubscription<dynamic> sub = receive.listen((dynamic message) {
      if (message is _HandshakeMessage) {
        control = message.controlPort;
        lastWorkerIsolateId = message.isolateId;
        if (cancellation != null) {
          if (cancellation.isCancelled) {
            control?.send(_cancelSignal);
          } else {
            // Forward a late cancellation; the worker stops between chunks.
            pollTimer = Timer.periodic(_pollInterval, (Timer t) {
              if (cancellation.isCancelled) {
                control?.send(_cancelSignal);
                t.cancel();
              }
            });
          }
        }
      } else if (message is _ProgressMessage) {
        onProgress?.call(
          HashProgress(
            bytesHashed: message.bytesHashed,
            totalBytes: message.totalBytes,
          ),
        );
      } else if (message is _DoneMessage) {
        if (!completer.isCompleted) {
          completer.complete(message.toResult(absolutePath));
        }
      } else if (message is List) {
        // onError port: [errorString, stackString]. Never leak the stack trace.
        completeFailure('worker error');
      } else if (message == null) {
        // onExit port: the worker terminated. If it never produced a result,
        // recover with a safe failure instead of hanging forever.
        completeFailure('worker exited unexpectedly');
      }
    });

    try {
      isolate = await Isolate.spawn<_HashRequest>(
        _workerEntry,
        request,
        onError: receive.sendPort,
        onExit: receive.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      completeFailure('failed to start hashing worker');
    }

    try {
      return await completer.future;
    } finally {
      pollTimer?.cancel();
      await sub.cancel();
      receive.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  /// Worker isolate entry point. Streams the file in bounded chunks and reports
  /// progress / result back through [_HashRequest.sendPort].
  @pragma('vm:entry-point')
  static Future<void> _workerEntry(_HashRequest req) async {
    final ReceivePort controlPort = ReceivePort();
    bool cancelled = req.startCancelled;
    controlPort.listen((dynamic m) {
      if (m == _cancelSignal) cancelled = true;
    });

    final String isolateId =
        developer.Service.getIsolateId(Isolate.current) ??
        'iso-${identityHashCode(Isolate.current)}';
    req.sendPort.send(_HandshakeMessage(controlPort.sendPort, isolateId));

    // Test-only: simulate an unexpected worker crash after handshake. Thrown
    // outside the try/catch below so it propagates as a fatal isolate error,
    // exercising the caller's onError/onExit recovery.
    if (req.crashAfterHandshake) {
      throw StateError('debug worker crash');
    }

    void finish(_DoneMessage message) {
      req.sendPort.send(message);
      controlPort.close();
    }

    if (cancelled) {
      finish(_DoneMessage.cancelled());
      return;
    }

    final File file = File(req.path);
    RandomAccessFile? raf;

    Future<void> closeFile() async {
      try {
        await raf?.close();
      } on FileSystemException {
        // Closing a read handle cannot corrupt the source; ignore safely.
      } finally {
        raf = null;
      }
    }

    // The result is computed here and only sent to the caller (via `finish`,
    // below) after the file handle has been fully, awaited-closed. The
    // caller kills this isolate as soon as it receives that message; sending
    // it any earlier would race an in-flight `closeFile()` against
    // `Isolate.kill`, which can abandon the close mid-flight and leave the
    // OS file handle briefly held after the caller's Future resolves
    // (observed on Windows as a transient "file in use" on delete).
    _DoneMessage result;
    try {
      final RandomAccessFile opened;
      try {
        opened = await file.open();
        raf = opened;
      } on FileSystemException catch (e) {
        result = _DoneMessage.failure(
          ImportErrorCode.unreadable,
          e.osError?.message ?? 'unreadable',
        );
        await closeFile();
        finish(result);
        return;
      }

      final int total = await opened.length();
      final _DigestSink output = _DigestSink();
      final ByteConversionSink input = sha256.startChunkedConversion(output);
      int hashed = 0;
      while (true) {
        if (cancelled) {
          input.close();
          result = _DoneMessage.cancelled();
          await closeFile();
          finish(result);
          return;
        }
        final List<int> chunk = await opened.read(req.chunkSize);
        if (chunk.isEmpty) break;
        input.add(chunk);
        hashed += chunk.length;
        if (req.wantsProgress) {
          req.sendPort.send(_ProgressMessage(hashed, total));
        }
      }
      input.close();
      result = _DoneMessage.success(output.value!.toString());
    } on FileSystemException catch (e) {
      result = _DoneMessage.failure(
        ImportErrorCode.hashFailed,
        e.osError?.message ?? 'read failed',
      );
    } catch (_) {
      result = _DoneMessage.failure(
        ImportErrorCode.hashFailed,
        'hashing failed',
      );
    }
    await closeFile();
    finish(result);
  }
}

/// Control-port signal asking the worker to stop hashing.
const String _cancelSignal = 'cancel';

/// Request sent to the worker isolate. All fields are sendable.
class _HashRequest {
  const _HashRequest({
    required this.sendPort,
    required this.path,
    required this.chunkSize,
    required this.wantsProgress,
    required this.startCancelled,
    required this.crashAfterHandshake,
  });

  final SendPort sendPort;
  final String path;
  final int chunkSize;
  final bool wantsProgress;
  final bool startCancelled;
  final bool crashAfterHandshake;
}

/// Worker -> caller: the worker's control port and service-id (for diagnostics
/// and the off-isolate regression test).
class _HandshakeMessage {
  const _HandshakeMessage(this.controlPort, this.isolateId);

  final SendPort controlPort;
  final String? isolateId;
}

/// Worker -> caller: streaming progress.
class _ProgressMessage {
  const _ProgressMessage(this.bytesHashed, this.totalBytes);

  final int bytesHashed;
  final int totalBytes;
}

/// Worker -> caller: terminal result (success / safe failure / cancelled).
class _DoneMessage {
  const _DoneMessage._({this.hash, this.errorCode, this.message});

  factory _DoneMessage.success(String hash) => _DoneMessage._(hash: hash);

  factory _DoneMessage.failure(ImportErrorCode code, String message) =>
      _DoneMessage._(errorCode: code, message: message);

  factory _DoneMessage.cancelled() => const _DoneMessage._(
    errorCode: ImportErrorCode.hashCancelled,
    message: 'hashing cancelled',
  );

  final String? hash;
  final ImportErrorCode? errorCode;
  final String? message;

  Sha256Result toResult(String path) {
    if (hash != null) return Sha256Result.success(hash!);
    return Sha256Result.failure(
      ImportError(code: errorCode!, path: path, message: message),
    );
  }
}

/// Minimal sink that captures the single emitted [Digest].
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
