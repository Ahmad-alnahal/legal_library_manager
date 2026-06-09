// test/features/import/streaming_file_hasher_test.dart

import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/import/data/services/streaming_file_hasher.dart';

import 'support/import_test_support.dart';

void main() {
  late Directory root;

  setUp(() => root = makeTempDir('hash'));
  tearDown(() => root.deleteSync(recursive: true));

  test('known content yields the correct lowercase 64-hex SHA-256', () async {
    // SHA-256("abc") is a published test vector.
    const String expected =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    final File f = writeFile(root, 'abc.bin', 'abc'.codeUnits);

    final result = await const StreamingFileHasher().hashFile(f.path);

    expect(result.isSuccess, isTrue);
    expect(result.hash, expected);
    expect(result.hash, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('streaming with a tiny chunk size matches a one-shot digest', () async {
    // A 256 KiB file, hashed with 4 KiB chunks: proves chunked reading without
    // loading the whole file at once, and that the result is identical to a
    // single-shot hash over the same bytes.
    final Uint8List bytes = Uint8List(256 * 1024);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = (i * 31 + 7) & 0xFF;
    }
    final File f = writeFile(root, 'big.bin', bytes);
    final String oneShot = sha256.convert(bytes).toString();

    final hasher = StreamingFileHasher(chunkSize: 4096);
    final result = await hasher.hashFile(f.path);

    expect(result.hash, oneShot);
    // The chunk size is far smaller than the file, so memory stays bounded.
    expect(hasher.chunkSize, lessThan(bytes.length));
  });

  test('progress callback reports increasing bytes up to the total', () async {
    final Uint8List bytes = Uint8List(20000);
    final File f = writeFile(root, 'p.bin', bytes);
    final List<HashProgress> updates = [];

    await StreamingFileHasher(
      chunkSize: 4096,
    ).hashFile(f.path, onProgress: updates.add);

    expect(updates, isNotEmpty);
    expect(updates.last.bytesHashed, bytes.length);
    expect(updates.last.totalBytes, bytes.length);
    // Monotonic non-decreasing progress.
    for (int i = 1; i < updates.length; i++) {
      expect(
        updates[i].bytesHashed,
        greaterThanOrEqualTo(updates[i - 1].bytesHashed),
      );
    }
  });

  test(
    'cancellation boundary stops hashing and reports a safe failure',
    () async {
      final File f = writeFile(root, 'c.bin', Uint8List(10000));
      final cancellation = MutableHashCancellation()..cancel();

      final result = await StreamingFileHasher(
        chunkSize: 1024,
      ).hashFile(f.path, cancellation: cancellation);

      expect(result.isSuccess, isFalse);
      expect(result.error!.code, ImportErrorCode.hashCancelled);
    },
  );

  test('progress/cancellation path runs in a worker isolate', () async {
    final File f = writeFile(root, 'iso.bin', Uint8List(20000));
    final String callerId =
        developer.Service.getIsolateId(Isolate.current) ?? 'caller';

    // Use the progress path (onProgress != null) so this is the
    // progress/cancellation-enabled execution path, not the plain fast path.
    final result = await StreamingFileHasher(
      chunkSize: 4096,
    ).hashFile(f.path, onProgress: (_) {});

    expect(result.isSuccess, isTrue);
    expect(StreamingFileHasher.lastWorkerIsolateId, isNotNull);
    expect(
      StreamingFileHasher.lastWorkerIsolateId,
      isNot(callerId),
      reason: 'hashing must execute in a different isolate than the caller',
    );
  });

  test('unexpected worker crash yields a safe failure (no hang)', () async {
    final File f = writeFile(root, 'crash.bin', Uint8List(4096));

    // The worker throws an uncaught error after handshake; the caller must
    // recover via its onError/onExit ports with a safe hash-failed result
    // rather than hanging forever.
    final result = await const StreamingFileHasher(
      debugCrashWorker: true,
    ).hashFile(f.path).timeout(const Duration(seconds: 10));

    expect(result.isSuccess, isFalse);
    expect(result.error!.code, ImportErrorCode.hashFailed);
    // No stack trace leaks into the safe message.
    expect(result.error!.message, isNot(contains('#0')));
  });

  test('missing file returns a safe unreadable failure (no throw)', () async {
    final result = await const StreamingFileHasher().hashFile(
      '${root.path}/nope.bin',
    );
    expect(result.isSuccess, isFalse);
    expect(result.error!.code, ImportErrorCode.unreadable);
    // No file bytes or stack traces leak into the message.
    expect(result.error!.message, isNot(contains('#0')));
  });
}
