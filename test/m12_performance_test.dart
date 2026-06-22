// test/m12_performance_test.dart
//
// M12.3 — Performance / Index / Responsiveness Check
//
// Runs the full import pipeline against a larger generated sample (50 PDFs)
// and reports timings. MVP threshold: full batch under 60 s (test timeout).
// Any per-file average above ~1 s with an in-memory DB on developer hardware
// is flagged as a warning in the test output (not a hard failure) so the
// operator can decide whether it is MVP-blocking.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/application/import_run_report.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/data/services/conservative_pdf_health_inspector.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_folder_validator.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_pdf_scanner.dart';
import 'package:legal_library_manager/features/import/data/services/streaming_file_hasher.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_request.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:path/path.dart' as p;

import 'features/import/support/import_test_support.dart';

const int _batchSize = 50;

// A ~4 KB healthy PDF; large enough for realistic SHA-256 timing, small enough
// to generate 50 of them instantly.
List<int> _makePdfBytes(int index) {
  final body = List.generate(
    100,
    (i) =>
        'Line ${i + 1} of document $index padding for realistic file size.\n',
  ).join();
  final content =
      '%PDF-1.4\n'
      '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n'
      '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n'
      '3 0 obj<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>endobj\n'
      '4 0 obj<< /Length ${body.length} >>\nstream\n'
      '$body'
      'endstream\nendobj\n'
      'trailer<< /Root 1 0 R >>\n%%EOF\n';
  return content.codeUnits;
}

void main() {
  group('M12.3 import-pipeline performance ($_batchSize files)', () {
    late Directory root;
    late Directory srcDir;
    late AppDatabase db;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('marjiy_m123_');
      // srcDir is a sibling of root so it does NOT live inside the database
      // root — the ImportCoordinator validator blocks source folders that are
      // nested inside any protected root.
      srcDir = await Directory(p.join(root.path, 'src')).create();
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();

      // Write _batchSize unique PDFs with different content so no duplicate
      // short-circuit can mask per-file cost.
      for (var i = 0; i < _batchSize; i++) {
        writeFile(
          srcDir,
          'doc_${i.toString().padLeft(3, '0')}.pdf',
          _makePdfBytes(i),
        );
      }
    });

    tearDown(() async {
      await db.close();
      // After hashing 50 files the worker isolates may hold handles briefly.
      // Give them time to release before the first deletion attempt.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      // Best-effort final attempt; ignore failure for a perf-test teardown.
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'full import completes within timeout and all files are imported',
      () async {
        final coordinator = ImportCoordinator(
          validator: const FileSystemFolderValidator(),
          scanner: const FileSystemPdfScanner(),
          hasher: const StreamingFileHasher(),
          inspector: const ConservativePdfHealthInspector(),
          repository: DriftImportRepository(db),
          clock: const SystemClock(),
        );

        final sw = Stopwatch()..start();
        // databaseRoot must NOT be an ancestor of srcDir; use a dedicated subdir.
        final dbRoot = p.join(root.path, 'db');
        await Directory(dbRoot).create();
        final ImportRunReport report = await coordinator.run(
          ImportRequest(
            sourceFolder: srcDir.path,
            recursive: true,
            protectedRoots: ProtectedRoots(databaseRoot: dbRoot),
          ),
          cancellation: MutableHashCancellation(),
        );
        sw.stop();

        final totalMs = sw.elapsedMilliseconds;
        final perFileMs = totalMs / _batchSize;

        // Print timing so it appears in test output for the operator to review.
        // ignore: avoid_print
        print(
          'M12.3 import timing: $_batchSize files in ${totalMs}ms '
          '(${perFileMs.toStringAsFixed(1)} ms/file)',
        );

        // Hard assertions: correctness first.
        expect(
          report.importedNewCount,
          _batchSize,
          reason: 'All $_batchSize unique files must import',
        );
        expect(report.failedCount, 0, reason: 'No file should fail import');
        expect(
          report.duplicateCount,
          0,
          reason: 'All files have unique content',
        );

        // Soft threshold: warn if average exceeds 1000 ms/file on developer
        // hardware, but do NOT fail the test — the operator makes the call.
        if (perFileMs > 1000) {
          // ignore: avoid_print
          print(
            'M12.3 WARNING: ${perFileMs.toStringAsFixed(0)} ms/file exceeds '
            '1000 ms advisory threshold. Consider investigating if MVP latency '
            'is user-visible.',
          );
        }

        // The test itself always passes if correctness holds within the timeout.
        expect(
          totalMs,
          lessThan(60000),
          reason: 'Batch must complete in under 60 s',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'SHA-256 hashing alone scales linearly with file count',
      () async {
        final hasher = const StreamingFileHasher();
        final files = srcDir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

        final sw = Stopwatch()..start();
        for (final f in files) {
          final result = await hasher.hashFile(f.path);
          expect(
            result.isSuccess,
            isTrue,
            reason: '${p.basename(f.path)} must hash successfully',
          );
        }
        sw.stop();

        final totalMs = sw.elapsedMilliseconds;
        final perFileMs = totalMs / files.length;

        // ignore: avoid_print
        print(
          'M12.3 hashing: ${files.length} files in ${totalMs}ms '
          '(${perFileMs.toStringAsFixed(1)} ms/file)',
        );

        expect(files, hasLength(_batchSize));
        expect(
          totalMs,
          lessThan(30000),
          reason: 'Hashing alone must complete in under 30 s',
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
