// test/features/import/pdf_scanner_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/data/services/file_system_pdf_scanner.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_request.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:path/path.dart' as p;

import 'support/import_test_support.dart';

void main() {
  const FileSystemPdfScanner scanner = FileSystemPdfScanner();

  late Directory root;
  late Directory source;
  late Directory dbRoot;

  setUp(() {
    root = makeTempDir('scan');
    source = Directory(p.join(root.path, 'src'))..createSync();
    dbRoot = Directory(p.join(root.path, 'app_support'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  ImportRequest request({required bool recursive, ProtectedRoots? roots}) =>
      ImportRequest(
        sourceFolder: source.path,
        recursive: recursive,
        protectedRoots: roots ?? ProtectedRoots(databaseRoot: dbRoot.path),
      );

  List<String> names(PdfScanResult r) =>
      r.candidates.map((c) => c.fileName).toList();

  test('non-recursive scan returns only top-level PDFs', () async {
    writeFile(source, 'a.pdf', healthyPdfBytes());
    final Directory sub = Directory(p.join(source.path, 'sub'))..createSync();
    writeFile(sub, 'b.pdf', healthyPdfBytes());

    final r = await scanner.scan(request(recursive: false));
    expect(names(r), ['a.pdf']);
  });

  test('recursive scan descends into subfolders', () async {
    writeFile(source, 'a.pdf', healthyPdfBytes());
    final Directory sub = Directory(p.join(source.path, 'sub'))..createSync();
    writeFile(sub, 'b.pdf', healthyPdfBytes());

    final r = await scanner.scan(request(recursive: true));
    expect(names(r).toSet(), {'a.pdf', 'b.pdf'});
  });

  test('.PDF extension matches case-insensitively', () async {
    writeFile(source, 'UPPER.PDF', healthyPdfBytes());
    writeFile(source, 'Mixed.Pdf', healthyPdfBytes());

    final r = await scanner.scan(request(recursive: false));
    expect(names(r).toSet(), {'UPPER.PDF', 'Mixed.Pdf'});
    // Extensions are normalized lowercase.
    expect(r.candidates.every((c) => c.extension == '.pdf'), isTrue);
  });

  test('unsupported files are excluded (no doc/docx/txt in MVP)', () async {
    writeFile(source, 'keep.pdf', healthyPdfBytes());
    writeFile(source, 'skip.docx', 'x'.codeUnits);
    writeFile(source, 'skip.doc', 'x'.codeUnits);
    writeFile(source, 'skip.txt', 'x'.codeUnits);

    final r = await scanner.scan(request(recursive: false));
    expect(names(r), ['keep.pdf']);
  });

  test('ordering is deterministic (case-insensitive path order)', () async {
    writeFile(source, 'c.pdf', healthyPdfBytes());
    writeFile(source, 'A.pdf', healthyPdfBytes());
    writeFile(source, 'b.pdf', healthyPdfBytes());

    final r1 = await scanner.scan(request(recursive: true));
    final r2 = await scanner.scan(request(recursive: true));
    expect(names(r1), names(r2));
    expect(names(r1), ['A.pdf', 'b.pdf', 'c.pdf']);
  });

  test('does not descend into a protected root nested in the source', () async {
    writeFile(source, 'top.pdf', healthyPdfBytes());
    final Directory protectedDir = Directory(p.join(source.path, 'protected'))
      ..createSync();
    writeFile(protectedDir, 'secret.pdf', healthyPdfBytes());

    final r = await scanner.scan(
      request(
        recursive: true,
        roots: ProtectedRoots(
          databaseRoot: dbRoot.path,
          managedLibraryRoot: protectedDir.path,
        ),
      ),
    );
    expect(names(r), ['top.pdf']);
  });

  test('candidate metadata exposes size and canonical path', () async {
    final File f = writeFile(source, 'a.pdf', healthyPdfBytes());
    final r = await scanner.scan(request(recursive: false));
    final PdfCandidate c = r.candidates.single;
    expect(c.sizeBytes, f.lengthSync());
    expect(p.isAbsolute(c.absolutePath), isTrue);
  });
}
