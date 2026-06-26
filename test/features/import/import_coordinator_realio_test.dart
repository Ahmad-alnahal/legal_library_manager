// test/features/import/import_coordinator_realio_test.dart

import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/data/services/conservative_pdf_health_inspector.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_folder_validator.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_pdf_scanner.dart';
import 'package:legal_library_manager/features/import/data/services/streaming_file_hasher.dart';
import 'package:legal_library_manager/features/import/application/import_file_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_request.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_health_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:path/path.dart' as p;

import 'support/import_test_support.dart';

Future<void> _deleteTempDirSafely(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  test('real PDF scanner runs correctly on a background isolate', () async {
    final Directory root = makeTempDir('iso_scan');
    addTearDown(() => _deleteTempDirSafely(root));
    final Directory src = Directory(p.join(root.path, 'src'))..createSync();
    final Directory dbRoot = Directory(p.join(root.path, 'db'))..createSync();
    writeFile(src, 'a.pdf', healthyPdfBytes());

    final request = ImportRequest(
      sourceFolder: src.path,
      recursive: true,
      protectedRoots: ProtectedRoots(databaseRoot: dbRoot.path),
    );

    final PdfScanResult result = await Isolate.run(
      () => const FileSystemPdfScanner().scan(request),
    );
    expect(result.candidates.map((c) => c.fileName), ['a.pdf']);
  });

  test(
    'real PDF health inspector runs correctly on a background isolate',
    () async {
      final Directory root = makeTempDir('iso_health');
      addTearDown(() => _deleteTempDirSafely(root));
      final File f = writeFile(root, 'ok.pdf', healthyPdfBytes());

      final PdfHealthResult health = await Isolate.run(
        () => const ConservativePdfHealthInspector().inspect(f.path),
      );
      expect(health.status, PdfHealthStatus.healthy);
    },
  );

  test(
    'full run with real services imports and leaves source files unchanged',
    () async {
      final Directory root = makeTempDir('coord_real');
      addTearDown(() => _deleteTempDirSafely(root));
      final Directory src = Directory(p.join(root.path, 'src'))..createSync();
      final Directory dbRoot = Directory(p.join(root.path, 'db'))..createSync();
      final File a = writeFile(src, 'a.pdf', healthyPdfBytes());
      final File b = writeFile(src, 'b.pdf', healthyPdfBytes()); // duplicate

      final Map<String, ({List<int> bytes, DateTime mtime})> before = {
        for (final File f in [a, b])
          f.path: (bytes: f.readAsBytesSync(), mtime: f.lastModifiedSync()),
      };

      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      await ReferenceSeeder(db).seedAll();

      // Default runner = Isolate.run, so scan + health run off the caller.
      final coordinator = ImportCoordinator(
        validator: const FileSystemFolderValidator(),
        scanner: const FileSystemPdfScanner(),
        hasher: const StreamingFileHasher(),
        inspector: const ConservativePdfHealthInspector(),
        repository: DriftImportRepository(db),
        clock: const SystemClock(),
      );

      final report = await coordinator.run(
        ImportRequest(
          sourceFolder: src.path,
          recursive: true,
          protectedRoots: ProtectedRoots(databaseRoot: dbRoot.path),
        ),
        cancellation: MutableHashCancellation(),
      );

      expect(report.status, ImportBatchStatus.completed);
      // Identical bytes -> one new + one duplicate.
      expect(report.importedNewCount, 1);
      expect(report.duplicateCount, 1);

      // Source files are byte- and timestamp-identical afterwards.
      for (final File f in [a, b]) {
        expect(f.existsSync(), isTrue);
        expect(f.readAsBytesSync(), before[f.path]!.bytes);
        expect(f.lastModifiedSync(), before[f.path]!.mtime);
      }
      expect(src.listSync().map((e) => p.basename(e.path)).toSet(), {
        'a.pdf',
        'b.pdf',
      });
    },
  );

  test(
    'zero-byte PDF produces a corrupted result and leaves source bytes unchanged',
    () async {
      final Directory root = makeTempDir('coord_zero');
      addTearDown(() => _deleteTempDirSafely(root));
      final Directory src = Directory(p.join(root.path, 'src'))..createSync();
      final Directory dbRoot = Directory(p.join(root.path, 'db'))..createSync();

      final File good = writeFile(src, 'good.pdf', healthyPdfBytes());
      final File broken = writeFile(src, 'broken.pdf', []); // zero bytes

      final List<int> brokenBytesBefore = broken.readAsBytesSync();
      final DateTime brokenMtimeBefore = broken.lastModifiedSync();

      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      await ReferenceSeeder(db).seedAll();

      final coordinator = ImportCoordinator(
        validator: const FileSystemFolderValidator(),
        scanner: const FileSystemPdfScanner(),
        hasher: const StreamingFileHasher(),
        inspector: const ConservativePdfHealthInspector(),
        repository: DriftImportRepository(db),
        clock: const SystemClock(),
      );

      final report = await coordinator.run(
        ImportRequest(
          sourceFolder: src.path,
          recursive: true,
          protectedRoots: ProtectedRoots(databaseRoot: dbRoot.path),
        ),
        cancellation: MutableHashCancellation(),
      );

      expect(report.status, ImportBatchStatus.completed);
      expect(report.importedNewCount, 1);
      expect(report.failedCount, 1);

      final corruptedReports = report.files
          .where((f) => f.status == ImportFileStatus.corrupted)
          .toList();
      expect(corruptedReports.length, 1);
      expect(corruptedReports.single.fileName, 'broken.pdf');

      // Source directory is untouched.
      expect(good.existsSync(), isTrue);
      expect(broken.existsSync(), isTrue);
      expect(broken.readAsBytesSync(), brokenBytesBefore);
      expect(broken.lastModifiedSync(), brokenMtimeBefore);
    },
  );

  test(
    'bad-header PDF (non-zero-byte corrupted) produces a corrupted result',
    () async {
      final Directory root = makeTempDir('coord_badhdr');
      addTearDown(() => _deleteTempDirSafely(root));
      final Directory src = Directory(p.join(root.path, 'src'))..createSync();
      final Directory dbRoot = Directory(p.join(root.path, 'db'))..createSync();

      writeFile(src, 'corrupt.pdf', corruptedPdfBytes()); // non-PDF header

      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      await ReferenceSeeder(db).seedAll();

      final coordinator = ImportCoordinator(
        validator: const FileSystemFolderValidator(),
        scanner: const FileSystemPdfScanner(),
        hasher: const StreamingFileHasher(),
        inspector: const ConservativePdfHealthInspector(),
        repository: DriftImportRepository(db),
        clock: const SystemClock(),
      );

      final report = await coordinator.run(
        ImportRequest(
          sourceFolder: src.path,
          recursive: true,
          protectedRoots: ProtectedRoots(databaseRoot: dbRoot.path),
        ),
        cancellation: MutableHashCancellation(),
      );

      expect(report.status, ImportBatchStatus.completed);
      expect(report.files.single.status, ImportFileStatus.corrupted);
      expect(report.importedNewCount, 0);
      expect(report.failedCount, 1);
      expect(report.hasRetryableFailures, isTrue);
    },
  );
}
