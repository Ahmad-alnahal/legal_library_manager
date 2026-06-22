// test/features/import/import_pipeline_safety_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/data/services/conservative_pdf_health_inspector.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_pdf_scanner.dart';
import 'package:legal_library_manager/features/import/data/services/streaming_file_hasher.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_request.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_health_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/prepared_source_file.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:path/path.dart' as p;

import 'support/import_test_support.dart';

/// End-to-end safety: scanning, hashing, health, and persistence must leave the
/// original source files byte-for-byte and timestamp identical (copy-only rule).
void main() {
  test('source files are unchanged after a full import pipeline run', () async {
    final Directory root = makeTempDir('pipeline');
    // On Windows a worker isolate may hold a file handle briefly after the
    // Future resolves. Retry deletion a few times before letting it throw.
    addTearDown(() async {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      }
      root.deleteSync(recursive: true);
    });
    final Directory source = Directory(p.join(root.path, 'src'))..createSync();
    final Directory dbRoot = Directory(p.join(root.path, 'app_support'))
      ..createSync();

    final File a = writeFile(source, 'a.pdf', healthyPdfBytes());
    final File b = writeFile(source, 'b.pdf', healthyPdfBytes());

    // Snapshot the originals.
    final Map<String, ({List<int> bytes, DateTime mtime})> before = {
      for (final File f in [a, b])
        f.path: (bytes: f.readAsBytesSync(), mtime: f.lastModifiedSync()),
    };

    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    await ReferenceSeeder(db).seedAll();
    final repo = DriftImportRepository(db);

    const scanner = FileSystemPdfScanner();
    const hasher = StreamingFileHasher();
    const inspector = ConservativePdfHealthInspector();

    final request = ImportRequest(
      sourceFolder: source.path,
      recursive: true,
      protectedRoots: ProtectedRoots(databaseRoot: dbRoot.path),
    );

    final scan = await scanner.scan(request);
    expect(scan.candidates.length, 2);

    for (final PdfCandidate c in scan.candidates) {
      final hashResult = await hasher.hashFile(c.absolutePath);
      final health = await inspector.inspect(c.absolutePath);
      expect(hashResult.isSuccess, isTrue);
      expect(health.status, PdfHealthStatus.healthy);

      await repo.persistHashedFile(
        PreparedSourceFile(
          canonicalPath: c.absolutePath,
          displayName: c.fileName,
          extension: c.extension,
          sizeBytes: c.sizeBytes,
          sha256: hashResult.hash!,
          health: health.status,
          mimeType: 'application/pdf',
          pageCount: health.pageCount,
        ),
        operationId: 'op-${c.fileName}',
        now: DateTime.utc(2026, 6, 8),
      );
    }

    // Verify nothing about the originals changed.
    for (final File f in [a, b]) {
      expect(f.existsSync(), isTrue, reason: '${f.path} must still exist');
      expect(f.readAsBytesSync(), before[f.path]!.bytes);
      expect(f.lastModifiedSync(), before[f.path]!.mtime);
    }
    // Filenames are unchanged (same directory listing).
    final names = source.listSync().map((e) => p.basename(e.path)).toSet();
    expect(names, {'a.pdf', 'b.pdf'});
  });
}
