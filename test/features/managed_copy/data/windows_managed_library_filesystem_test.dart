import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/data/services/windows_managed_library_filesystem.dart';

void main() {
  test(
    'finds only strict current-document MARJIY recovery artifacts',
    () async {
      final root = await Directory.systemTemp.createTemp('marjiy-recovery-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });

      for (final name in [
        'DOC-0000001.pdf',
        'DOC-0000001.pdf.copy_123_abcdef.copying',
        'DOC-0000002.pdf',
        'DOC-0000001.pdf.copying',
        'notes.txt',
      ]) {
        await File('${root.path}\\$name').writeAsString('test');
      }
      final nested = await Directory('${root.path}\\nested').create();
      await File(
        '${nested.path}\\DOC-0000001.pdf.copy_x.copying',
      ).writeAsString('test');

      const filesystem = WindowsManagedLibraryFilesystem();
      final artifacts = await filesystem.findRecoveryArtifacts(
        root.path,
        'DOC-0000001',
      );

      expect(artifacts, isNotNull);
      final found = artifacts!;
      // Only in-progress .copying temp files are returned; the final .pdf is
      // handled separately by the use case and must NOT appear here.
      expect(found, hasLength(1));
      expect(found.any((p) => p.endsWith('.copy_123_abcdef.copying')), isTrue);
      expect(found.any((p) => p.endsWith('DOC-0000001.pdf')), isFalse);
    },
  );

  test(
    'startup inspection finds copying files and unregistered final files only',
    () async {
      final root = await Directory.systemTemp.createTemp('marjiy-startup-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });

      for (final name in [
        'DOC-0000001.pdf',
        'DOC-0000001.pdf.copy_123_abcdef.copying',
        'DOC-0000002.pdf',
        'DOC-0000002.pdf.copying',
        'DOC-ABC.pdf.copy_123.copying',
        'notes.txt',
      ]) {
        await File('${root.path}\\$name').writeAsString('test');
      }
      final nested = await Directory('${root.path}\\nested').create();
      await File(
        '${nested.path}\\DOC-0000003.pdf.copy_x.copying',
      ).writeAsString('test');

      const filesystem = WindowsManagedLibraryFilesystem();
      final artifacts = await filesystem.findStartupRecoveryArtifacts(
        root.path,
        ['DOC-0000001'],
      );

      expect(artifacts, isNotNull);
      final found = artifacts!;
      expect(found, hasLength(2));
      expect(
        found.any((p) => p.endsWith('DOC-0000001.pdf.copy_123_abcdef.copying')),
        isTrue,
      );
      expect(found.any((p) => p.endsWith('DOC-0000002.pdf')), isTrue);
      expect(found.any((p) => p.endsWith('DOC-0000001.pdf')), isFalse);
      expect(found.any((p) => p.endsWith('DOC-0000002.pdf.copying')), isFalse);
      expect(found.any((p) => p.contains('nested')), isFalse);
    },
  );

  test(
    'startup backup inspection finds strict incomplete backup files only',
    () async {
      final root = await Directory.systemTemp.createTemp('marjiy-backups-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });

      await File(
        '${root.path}\\legal_library_backup_2026-06-21_164400_manual.sqlite',
      ).writeAsBytes(const []);
      await File(
        '${root.path}\\legal_library_backup_2026-06-21_164401_manual.sqlite',
      ).writeAsBytes(List<int>.filled(256, 1));
      await File(
        '${root.path}\\DOC-9999999.pdf.test.copying',
      ).writeAsString('wrong folder');
      await File('${root.path}\\notes.sqlite').writeAsBytes(const []);
      final nested = await Directory('${root.path}\\nested').create();
      await File(
        '${nested.path}\\legal_library_backup_2026-06-21_164402_manual.sqlite',
      ).writeAsBytes(const []);

      const filesystem = WindowsManagedLibraryFilesystem();
      final artifacts = await filesystem.findStartupBackupArtifacts(root.path);

      expect(artifacts, isNotNull);
      final found = artifacts!;
      expect(found, hasLength(1));
      expect(
        found.single.endsWith(
          'legal_library_backup_2026-06-21_164400_manual.sqlite',
        ),
        isTrue,
      );
      expect(found.any((p) => p.contains('DOC-9999999')), isFalse);
      expect(found.any((p) => p.contains('nested')), isFalse);
    },
  );
}
