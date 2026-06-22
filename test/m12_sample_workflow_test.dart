// test/m12_sample_workflow_test.dart
//
// M12.2 — Realistic Sample Workflow Acceptance
//
// Exercises the full MVP chain with a disposable copied dataset:
//   import → duplicate/corrupted detection → classify → managed copy →
//   backup → integrity reconciliation → missing detection → restore.
//
// Source files are never modified. All app-created artefacts land only in
// the configured managed/backup directories.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/application/import_file_report.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/data/services/conservative_pdf_health_inspector.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_folder_validator.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_pdf_scanner.dart';
import 'package:legal_library_manager/features/import/data/services/streaming_file_hasher.dart';
import 'package:drift/drift.dart' show Value;
import 'package:legal_library_manager/features/import/application/import_run_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_request.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/managed_copy/application/managed_copy_use_case.dart';
import 'package:legal_library_manager/features/managed_copy/application/reconcile_managed_copy_integrity.dart';
import 'package:legal_library_manager/features/managed_copy/data/repositories/drift_managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/data/services/default_operation_id_generator.dart';
import 'package:legal_library_manager/features/managed_copy/data/services/sqlite_database_backup_service.dart';
import 'package:legal_library_manager/features/managed_copy/data/services/windows_managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/data/services/windows_path_canonicalizer.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_result.dart';
import 'package:path/path.dart' as p;

import 'features/import/support/import_test_support.dart';

// ── Test repository: thin override for the platform-channel database root ─────
//
// DriftManagedCopyRepository.loadDatabaseRoot() calls
// getApplicationSupportDirectory() (a platform channel that never completes in
// the flutter_test harness). This subclass replaces just that method with a
// caller-supplied temp path so every other Drift operation remains real.

class _TestManagedCopyRepo extends DriftManagedCopyRepository {
  _TestManagedCopyRepo(super.db, super.clock, this._dbRoot);
  final String _dbRoot;

  @override
  Future<String> loadDatabaseRoot() async => _dbRoot;
}

// ── Sample PDF content ────────────────────────────────────────────────────────

/// Content A: shared by alpha.pdf and gamma.pdf → gamma is an exact duplicate.
List<int> _contentA() => healthyPdfBytes();

/// Content B: unique bytes for beta.pdf (different from A → not a duplicate).
List<int> _contentB() {
  const s =
      '%PDF-1.4\n'
      '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n'
      '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n'
      '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj\n'
      'trailer<< /Root 1 0 R >>\n'
      '%%EOF\n';
  return s.codeUnits;
}

// ── Test ──────────────────────────────────────────────────────────────────────

void main() {
  group('M12.2 realistic sample workflow', () {
    late Directory root;
    late Directory srcDir;
    late Directory managedDir;
    late Directory backupDir;
    late Directory dbDir;
    late AppDatabase db;
    late _TestManagedCopyRepo repo;

    // Source files — never modified by the app.
    late File alphaFile; // healthy PDF, content A
    late File betaFile; // healthy PDF, content B (unique)
    late File gammaFile; // healthy PDF, content A → exact duplicate of alpha
    late File deltaFile; // corrupted (bad header)

    setUp(() async {
      root = await Directory.systemTemp.createTemp('marjiy_m12_');
      srcDir = await Directory(p.join(root.path, 'src')).create();
      managedDir = await Directory(p.join(root.path, 'managed')).create();
      backupDir = await Directory(p.join(root.path, 'backup')).create();
      dbDir = await Directory(p.join(root.path, 'db')).create();

      // File-based database so VACUUM INTO works during backup.
      db = AppDatabase.forExecutor(
        NativeDatabase(File(p.join(dbDir.path, 'legal_library.sqlite'))),
      );
      await ReferenceSeeder(db).seedAll();

      repo = _TestManagedCopyRepo(db, const SystemClock(), dbDir.path);

      // Create the four disposable source files.
      alphaFile = writeFile(srcDir, 'alpha.pdf', _contentA());
      betaFile = writeFile(srcDir, 'beta.pdf', _contentB());
      gammaFile = writeFile(srcDir, 'gamma.pdf', _contentA()); // same as alpha
      deltaFile = writeFile(srcDir, 'delta.pdf', corruptedPdfBytes());
    });

    tearDown(() async {
      await db.close();
      // On Windows an isolate may hold a file handle briefly after the Future
      // resolves. Retry deletion a few times before letting it throw.
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

    test(
      'full import → classify → managed copy → integrity reconciliation',
      () async {
        // ── Phase 1: Snapshot source files ─────────────────────────────────────

        final snapshot = <String, ({List<int> bytes, DateTime mtime})>{
          for (final f in [alphaFile, betaFile, gammaFile, deltaFile])
            f.path: (bytes: f.readAsBytesSync(), mtime: f.lastModifiedSync()),
        };

        void assertSourceUnchanged() {
          for (final f in [alphaFile, betaFile, gammaFile, deltaFile]) {
            expect(
              f.existsSync(),
              isTrue,
              reason: '${p.basename(f.path)} must still exist',
            );
            expect(
              f.readAsBytesSync(),
              snapshot[f.path]!.bytes,
              reason: '${p.basename(f.path)} content must not change',
            );
            expect(
              f.lastModifiedSync(),
              snapshot[f.path]!.mtime,
              reason: '${p.basename(f.path)} mtime must not change',
            );
          }
          expect(
            srcDir.listSync().map((e) => p.basename(e.path)).toSet(),
            {'alpha.pdf', 'beta.pdf', 'gamma.pdf', 'delta.pdf'},
            reason: 'source directory listing must be identical',
          );
        }

        // ── Phase 2: Import ─────────────────────────────────────────────────────

        final coordinator = ImportCoordinator(
          validator: const FileSystemFolderValidator(),
          scanner: const FileSystemPdfScanner(),
          hasher: const StreamingFileHasher(),
          inspector: const ConservativePdfHealthInspector(),
          repository: DriftImportRepository(db),
          clock: const SystemClock(),
        );

        final ImportRunReport report = await coordinator.run(
          ImportRequest(
            sourceFolder: srcDir.path,
            recursive: true,
            protectedRoots: ProtectedRoots(databaseRoot: dbDir.path),
          ),
          cancellation: MutableHashCancellation(),
        );

        // Import results: alpha → new, beta → new, gamma → duplicate of alpha,
        // delta → corrupted (failed).
        expect(report.status, ImportBatchStatus.completed);
        expect(
          report.importedNewCount,
          2,
          reason: 'alpha and beta are unique; gamma shares alpha content',
        );
        expect(
          report.duplicateCount,
          1,
          reason: 'gamma is an exact SHA-256 duplicate of alpha',
        );
        expect(report.failedCount, 1, reason: 'delta has a corrupted header');

        final corruptedFiles = report.files
            .where((f) => f.status == ImportFileStatus.corrupted)
            .toList();
        expect(corruptedFiles, hasLength(1));
        expect(corruptedFiles.single.fileName, 'delta.pdf');

        // Source files are unchanged immediately after import.
        assertSourceUnchanged();

        // ── Phase 3: Classify a document ────────────────────────────────────────
        //
        // beta.pdf was imported as its own unique logical document.
        // We locate its document_files row and directly update the workflow
        // status to `classified`, simulating the Review classification workflow
        // (which is tested separately in M6 tests).

        final betaFileRows = await (db.select(
          db.documentFiles,
        )..where((f) => f.fileName.equals('beta.pdf'))).get();
        expect(
          betaFileRows,
          hasLength(1),
          reason: 'beta must have one source file',
        );
        final betaDocId = betaFileRows.first.documentId;

        await (db.update(db.documents)..where((d) => d.id.equals(betaDocId)))
            .write(DocumentsCompanion(workflowStatusKey: Value('classified')));

        // Configure managed/backup roots in settings.
        await repo.saveCopyRoots(
          managedLibraryRoot: managedDir.path,
          backupRoot: backupDir.path,
        );

        // ── Phase 4: Managed copy ───────────────────────────────────────────────

        final useCase = ManagedCopyUseCase(
          repository: repo,
          filesystem: const WindowsManagedLibraryFilesystem(),
          backupService: SqliteDatabaseBackupService(db),
          hasher: const StreamingFileHasher(),
          clock: const SystemClock(),
          pathCanonicalizer: const WindowsPathCanonicalizer(),
          operationIdGenerator: const DefaultOperationIdGenerator(),
        );

        final copyResult = await useCase.execute(betaDocId);

        expect(
          copyResult,
          isA<ManagedCopySuccess>(),
          reason:
              'Managed copy must succeed for a classified document with a '
              'healthy source file, configured roots, and a successful backup',
        );
        final success = copyResult as ManagedCopySuccess;
        expect(
          success.documentCode,
          matches(r'^DOC-\d{7}$'),
          reason: 'Document code must use stable DOC-NNNNNNN format',
        );

        // ── Phase 5: Verify managed copy on disk ────────────────────────────────

        final managedFilesDir = Directory(p.join(managedDir.path, 'files'));
        expect(
          managedFilesDir.existsSync(),
          isTrue,
          reason: 'App must create managed/files/ directory',
        );

        final managedPdfs = managedFilesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .toList();
        expect(managedPdfs, hasLength(1), reason: 'Exactly one managed PDF');

        final managedPdf = managedPdfs.first;
        expect(
          p.basename(managedPdf.path),
          matches(r'^DOC-\d{7}\.pdf$'),
          reason: 'Managed filename must be the stable document code',
        );
        expect(
          managedPdf.readAsBytesSync(),
          _contentB(),
          reason: 'Managed copy content must match beta source exactly',
        );

        // No .copying temp files must remain after a successful copy.
        final copyingFiles = managedFilesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.copying'))
            .toList();
        expect(
          copyingFiles,
          isEmpty,
          reason: 'No .copying temp files must remain after successful copy',
        );

        // ── Phase 6: Backup created in backup root ──────────────────────────────

        final backupFiles = backupDir.listSync().whereType<File>().toList();
        expect(backupFiles, hasLength(1), reason: 'Exactly one backup file');
        expect(
          p.basename(backupFiles.single.path),
          matches(
            r'^legal_library_backup_\d{4}-\d{2}-\d{2}_\d{6}_copy_.+\.sqlite$',
          ),
          reason: 'Backup filename must follow the timestamped naming pattern',
        );
        expect(
          backupFiles.single.lengthSync(),
          greaterThan(1000),
          reason: 'Backup must be a real SQLite database file, not empty',
        );
        // Confirm the backup is a valid SQLite file.
        expect(
          SqliteDatabaseBackupService.verifyBackupFile(backupFiles.single.path),
          isTrue,
          reason:
              'Backup must pass the SQLite header + quick_check verification',
        );

        // Source files must still be unchanged after the managed copy.
        assertSourceUnchanged();

        // ── Phase 7: Integrity reconciliation — all healthy ──────────────────────

        final reconcile = ReconcileManagedCopyIntegrity(
          repository: repo,
          filesystem: const WindowsManagedLibraryFilesystem(),
          hasher: const StreamingFileHasher(),
          operationIdGenerator: const DefaultOperationIdGenerator(),
          clock: const SystemClock(),
        );

        final result1 = await reconcile();
        expect(result1.totalChecked, 1, reason: 'One managed copy row exists');
        expect(result1.healthyCount, 1);
        expect(result1.missingCount, 0);
        expect(result1.corruptedCount, 0);
        expect(result1.restoredCount, 0);

        // Document must still be copied_to_library.
        final docAfterCopy = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(betaDocId))).getSingle();
        expect(docAfterCopy.workflowStatusKey, 'copied_to_library');

        // ── Phase 8: Simulate managed copy gone missing ─────────────────────────

        // Move the managed PDF out of the files directory.
        final hiddenPath = p.join(root.path, '_hidden_beta.pdf');
        managedPdf.renameSync(hiddenPath);
        expect(
          managedPdf.existsSync(),
          isFalse,
          reason: 'Managed file must be absent to simulate missing',
        );

        final result2 = await reconcile();
        expect(
          result2.missingCount,
          1,
          reason: 'Missing file must be detected',
        );
        expect(result2.healthyCount, 0);

        // Document must be downgraded back to classified.
        final docAfterMissing = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(betaDocId))).getSingle();
        expect(
          docAfterMissing.workflowStatusKey,
          'classified',
          reason:
              'A document with no healthy managed copy must revert to classified',
        );

        // ── Phase 9: Restore managed copy and re-reconcile ──────────────────────

        // Move the PDF back into the managed files directory.
        File(hiddenPath).renameSync(managedPdf.path);
        expect(
          managedPdf.existsSync(),
          isTrue,
          reason: 'Managed file must be back in place',
        );

        final result3 = await reconcile();
        expect(
          result3.restoredCount,
          1,
          reason: 'Restored file must be reported',
        );
        // A "restored" file is distinct from "healthy" — the two counts are
        // mutually exclusive, so healthyCount remains 0 on this run.
        expect(result3.healthyCount, 0);
        expect(result3.missingCount, 0);

        // Document must return to copied_to_library after restoration.
        final docAfterRestore = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(betaDocId))).getSingle();
        expect(
          docAfterRestore.workflowStatusKey,
          'copied_to_library',
          reason:
              'Document must return to copied_to_library after its managed '
              'copy is restored',
        );

        // ── Phase 10: Final source safety check ─────────────────────────────────
        //
        // After the full workflow (import, managed copy, reconciliation
        // including missing + restore), source files must remain byte-for-byte
        // and timestamp-identical to their pre-workflow state.

        assertSourceUnchanged();

        // The managed and backup directories must contain only app-owned files.
        // Source directory must contain exactly the 4 original files.
        final finalSrcNames = srcDir
            .listSync()
            .map((e) => p.basename(e.path))
            .toSet();
        expect(finalSrcNames, {
          'alpha.pdf',
          'beta.pdf',
          'gamma.pdf',
          'delta.pdf',
        });

        // Managed files directory must contain exactly the one recovered PDF.
        final finalManagedPdfs = managedFilesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .toList();
        expect(
          finalManagedPdfs,
          hasLength(1),
          reason: 'Only one managed PDF must exist at the end',
        );
        expect(
          p.basename(finalManagedPdfs.single.path),
          matches(r'^DOC-\d{7}\.pdf$'),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
