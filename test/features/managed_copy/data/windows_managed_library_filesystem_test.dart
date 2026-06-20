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
}
