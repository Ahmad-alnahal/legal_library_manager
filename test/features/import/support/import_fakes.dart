// test/features/import/support/import_fakes.dart

import 'dart:async';

import 'package:legal_library_manager/features/import/application/folder_picker.dart';
import 'package:legal_library_manager/features/import/application/protected_roots_provider.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_record.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_file_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_request.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_health_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/prepared_source_file.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/repositories/import_repository.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/import/domain/services/folder_validator.dart';
import 'package:legal_library_manager/features/import/domain/services/pdf_health_inspector.dart';
import 'package:legal_library_manager/features/import/domain/services/pdf_scanner.dart';

/// Runs work synchronously in the caller isolate so fakes (not sendable across
/// isolates) work in deterministic coordinator tests.
Future<T> syncRunner<T>(FutureOr<T> Function() body) async => await body();

/// A runner that records how many times it was invoked while still executing
/// the body synchronously (so fakes work but call counts can be asserted).
class SpyRunner {
  int calls = 0;

  Future<T> run<T>(FutureOr<T> Function() body) async {
    calls++;
    return await body();
  }
}

class FakeFolderValidator implements FolderValidator {
  FakeFolderValidator(this.result);

  final FolderValidationResult result;
  int calls = 0;

  @override
  Future<FolderValidationResult> validate(
    String sourceFolder, {
    required ProtectedRoots protectedRoots,
  }) async {
    calls++;
    return result;
  }
}

class FakePdfScanner implements PdfScanner {
  FakePdfScanner(this.result);

  final PdfScanResult result;
  int calls = 0;

  @override
  Future<PdfScanResult> scan(ImportRequest request) async {
    calls++;
    return result;
  }
}

class FakePdfHealthInspector implements PdfHealthInspector {
  FakePdfHealthInspector({
    this.byPath = const {},
    PdfHealthResult? fallback,
    this.throwingPaths = const {},
  }) : fallback =
           fallback ??
           const PdfHealthResult(
             status: PdfHealthStatus.healthy,
             sizeBytes: 100,
             pageCount: 1,
           );

  final Map<String, PdfHealthResult> byPath;
  final PdfHealthResult fallback;

  /// Paths for which [inspect] throws, simulating unexpected service failures.
  final Set<String> throwingPaths;

  int calls = 0;

  @override
  Future<PdfHealthResult> inspect(String absolutePath) async {
    calls++;
    if (throwingPaths.contains(absolutePath)) {
      throw StateError('inspector failed unexpectedly (test)');
    }
    return byPath[absolutePath] ?? fallback;
  }
}

class FakeFileHasher implements FileHasher {
  FakeFileHasher({
    this.hashes = const {},
    this.failures = const {},
    this.throwingPaths = const {},
    this.cancelToken,
    this.cancelAfterPath,
    this.gate,
  });

  /// Path -> lowercase 64-hex hash. Missing paths get a derived stable hash.
  final Map<String, String> hashes;

  /// Paths that should fail hashing (returns a safe hash_failed result).
  final Set<String> failures;

  /// Paths for which [hashFile] throws, simulating unexpected service failures.
  final Set<String> throwingPaths;

  /// When set, this token is cancelled right after hashing [cancelAfterPath],
  /// so the coordinator stops before the next file.
  final MutableHashCancellation? cancelToken;
  final String? cancelAfterPath;

  /// Optional gate awaited on the first call (keeps a run "active").
  final Completer<void>? gate;

  int calls = 0;

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    if (gate != null && calls == 0) await gate!.future;
    calls++;
    if (cancellation?.isCancelled ?? false) {
      return Sha256Result.failure(
        const ImportError(code: ImportErrorCode.hashCancelled),
      );
    }
    if (throwingPaths.contains(absolutePath)) {
      throw StateError('hasher failed unexpectedly (test)');
    }
    if (failures.contains(absolutePath)) {
      return Sha256Result.failure(
        const ImportError(code: ImportErrorCode.hashFailed, message: 'failed'),
      );
    }
    final String hash = hashes[absolutePath] ?? _stableHash(absolutePath);
    if (cancelAfterPath == absolutePath) cancelToken?.cancel();
    return Sha256Result.success(hash);
  }

  String _stableHash(String path) {
    final int code = path.hashCode & 0xffff;
    final String hex = code.toRadixString(16).padLeft(4, '0');
    return (hex * 16).substring(0, 64);
  }
}

class FakeProtectedRootsProvider implements ProtectedRootsProvider {
  FakeProtectedRootsProvider(this.roots);

  final ProtectedRoots roots;

  @override
  Future<ProtectedRoots> load() async => roots;
}

class FakeFolderPicker implements FolderPicker {
  FakeFolderPicker(this.path, {this.throwOnPick = false, this.gate});

  String? path;

  /// When true, [pickDirectory] throws, simulating a native dialog failure.
  final bool throwOnPick;

  /// When set, [pickDirectory] resolves to this completer's value instead of
  /// [path], letting a test control when the dialog "returns".
  final Completer<String?>? gate;

  @override
  Future<String?> pickDirectory() async {
    if (throwOnPick) throw Exception('native picker failed');
    if (gate != null) return gate!.future;
    return path;
  }
}

/// In-memory [ImportRepository] for fast coordinator/UI tests that do not need a
/// real database. Per-path failure sets let tests exercise persistence-failure
/// isolation without a real Drift transaction.
class FakeImportRepository implements ImportRepository {
  FakeImportRepository({
    this.failPersistPaths = const {},
    this.failRecordPaths = const {},
    this.failOnComplete = false,
    this.failFailBatch = false,
    this.recentBatches = const [],
    this.failGetRecentBatches = false,
  });

  /// Source paths whose hashed/failed persistence should throw.
  final Set<String> failPersistPaths;

  /// Source paths whose file-less event recording should throw (including the
  /// secondary safe-logging attempt).
  final Set<String> failRecordPaths;

  /// When true, [completeBatch] throws — exercising the coordinator-level
  /// failure path that must preserve already-produced per-file reports.
  final bool failOnComplete;

  /// When true, [failBatch] also throws — exercising the [_failBatchSafely]
  /// best-effort path that must still return a safe failed report.
  final bool failFailBatch;

  final List<ImportBatchRecord> recentBatches;
  final bool failGetRecentBatches;

  int _batchSeq = 0;
  int _docSeq = 0;
  int _fileSeq = 0;

  ImportBatchStatus? lastStatus;
  bool clearedCompletedAt = false;
  int markInterruptedCalls = 0;

  /// The most recent [FailedSourceFile] passed to [persistFailedFile]. Useful
  /// for asserting that health statuses and error codes are preserved exactly.
  FailedSourceFile? lastFailedFile;

  @override
  Future<ImportBatchRef> createBatch({
    required String sourceFolder,
    required bool recursive,
    required DateTime now,
  }) async {
    _batchSeq++;
    return ImportBatchRef(id: _batchSeq, batchCode: 'IMPORT-$_batchSeq');
  }

  @override
  Future<void> updateBatchProgress(
    int batchId, {
    int? discoveredCount,
    int? importedCount,
    int? duplicateCount,
    int? failedCount,
    int? pairedCount,
    ImportBatchStatus? status,
    bool clearCompletedAt = false,
  }) async {
    if (status != null) lastStatus = status;
    if (clearCompletedAt) clearedCompletedAt = true;
  }

  @override
  Future<void> completeBatch(
    int batchId, {
    required int discoveredCount,
    required int importedCount,
    required int duplicateCount,
    required int failedCount,
    required int pairedCount,
    required DateTime now,
  }) async {
    if (failOnComplete) throw StateError('complete failed (test)');
    lastStatus = ImportBatchStatus.completed;
  }

  @override
  Future<void> markInterruptedBatches({required DateTime now}) async {
    markInterruptedCalls++;
  }

  @override
  Future<void> failBatch(int batchId, {required DateTime now}) async {
    if (failFailBatch) throw StateError('failBatch failed (test)');
    lastStatus = ImportBatchStatus.failed;
  }

  @override
  Future<void> cancelBatch(int batchId, {required DateTime now}) async {
    lastStatus = ImportBatchStatus.cancelled;
  }

  @override
  Future<List<ImportBatchRecord>> getRecentBatches({int limit = 20}) async {
    if (failGetRecentBatches) throw StateError('getRecentBatches failed (test)');
    return recentBatches.take(limit).toList();
  }

  @override
  Future<ExistingFileRef?> findByAbsolutePath(String canonicalPath) async =>
      null;

  @override
  Future<ImportFileResult> persistHashedFile(
    PreparedSourceFile file, {
    required String operationId,
    required DateTime now,
    int? batchId,
  }) async {
    if (failPersistPaths.contains(file.canonicalPath)) {
      throw StateError('persist failed (test)');
    }
    return ImportFileResult(
      outcome: ImportFileOutcome.importedNew,
      documentId: ++_docSeq,
      fileId: ++_fileSeq,
    );
  }

  @override
  Future<ImportFileResult> persistFailedFile(
    FailedSourceFile file, {
    required ImportFileOutcome outcome,
    required String operationId,
    required DateTime now,
    int? batchId,
  }) async {
    if (failPersistPaths.contains(file.canonicalPath)) {
      throw StateError('persist failed (test)');
    }
    lastFailedFile = file;
    return ImportFileResult(
      outcome: outcome,
      documentId: ++_docSeq,
      fileId: ++_fileSeq,
    );
  }

  @override
  Future<ImportFileResult> recordFilelessOutcome({
    required ImportFileOutcome outcome,
    required String sourcePath,
    required String operationId,
    required DateTime now,
    String? errorCode,
    String? safeMessage,
  }) async {
    if (failRecordPaths.contains(sourcePath)) {
      throw StateError('record failed (test)');
    }
    return ImportFileResult(outcome: outcome);
  }

  @override
  Future<ImportFileResult> persistPairedWordSource(
    PreparedSourceFile file, {
    required int existingDocumentId,
    required String operationId,
    required DateTime now,
    int? batchId,
  }) async {
    if (failPersistPaths.contains(file.canonicalPath)) {
      throw StateError('persist failed (test)');
    }
    return ImportFileResult(
      outcome: ImportFileOutcome.pairedWordSource,
      documentId: existingDocumentId,
      fileId: ++_fileSeq,
    );
  }
}

/// Builds a [PdfCandidate] for tests.
PdfCandidate candidate(
  String path, {
  String? name,
  int size = 100,
  String extension = '.pdf',
}) {
  final String base = name ?? path.split(RegExp(r'[\\/]')).last;
  return PdfCandidate(
    absolutePath: path,
    fileName: base,
    extension: extension,
    sizeBytes: size,
  );
}
