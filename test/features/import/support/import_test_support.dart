// test/features/import/support/import_test_support.dart

import 'dart:io';

import 'package:path/path.dart' as p;

/// A minimal but plausible single-page PDF: valid `%PDF-` header and exactly one
/// `/Type /Page` page object (the `/Type /Pages` tree node is excluded by the
/// conservative page-count heuristic).
List<int> healthyPdfBytes() {
  const String content =
      '%PDF-1.4\n'
      '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n'
      '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n'
      '3 0 obj<< /Type /Page /Parent 2 0 R >>endobj\n'
      'trailer<< /Root 1 0 R >>\n'
      '%%EOF\n';
  return content.codeUnits;
}

/// Bytes that are non-empty but lack a `%PDF-` header (corrupted).
List<int> corruptedPdfBytes() => 'NOT-A-PDF-FILE\n%%EOF'.codeUnits;

/// Writes [bytes] to `dir/name` and returns the file. Read/write only inside the
/// caller-provided temporary directory.
File writeFile(Directory dir, String name, List<int> bytes) {
  final File file = File(p.join(dir.path, name));
  file.writeAsBytesSync(bytes);
  return file;
}

/// Creates a uniquely-named temporary directory for a test and returns it.
Directory makeTempDir(String prefix) =>
    Directory.systemTemp.createTempSync('marjiy_${prefix}_');
