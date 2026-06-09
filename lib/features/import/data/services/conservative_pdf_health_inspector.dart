// lib/features/import/data/services/conservative_pdf_health_inspector.dart

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/pdf_health_result.dart';
import '../../domain/services/pdf_health_inspector.dart';

/// Conservative [PdfHealthInspector] with no heavy/licensed PDF dependency.
///
/// Checks existence, regular-file status, readable non-negative size, the `.pdf`
/// extension, and a plausible `%PDF-` header that may appear anywhere within the
/// PDF-spec-compatible initial prefix (not strictly at byte 0). Page count is a
/// strict, memory-bounded, streaming heuristic that only counts genuine
/// `/Type ... /Page` page-object markers with valid token boundaries; otherwise
/// it returns `null`. The file is only ever opened for reading and never
/// modified.
class ConservativePdfHealthInspector implements PdfHealthInspector {
  const ConservativePdfHealthInspector({this.chunkSize = _defaultChunkSize});

  /// `%PDF-` signature bytes.
  static const List<int> _signature = [0x25, 0x50, 0x44, 0x46, 0x2D];

  /// The PDF specification allows the header to appear within the first bytes of
  /// the file (some producers emit a small prefix/BOM). We search this many
  /// leading bytes for the signature.
  static const int _headerPrefixBytes = 1024;

  /// Only attempt the page-count heuristic for files at/under this size, to keep
  /// memory bounded. Larger files report a `null` page count.
  static const int _pageCountSizeCapBytes = 32 << 20; // 32 MiB.

  /// Default chunk size for streaming reads.
  static const int _defaultChunkSize = 1 << 20; // 1 MiB.

  /// Chunk size for streaming reads. Injectable so tests can exercise
  /// chunk-boundary marker matching with small chunks.
  final int chunkSize;

  /// The exact PDF white-space bytes (PDF 32000-1 §7.2): NUL, TAB, LF, FF, CR,
  /// and SPACE. Dart's `\s` additionally matches vertical tab and Unicode space
  /// separators (e.g. NBSP), which are NOT PDF white space, so it must not be
  /// used for PDF token boundaries.
  static const String _pdfWs = r'\x00\t\n\f\r ';

  /// Strict page-object marker: `/Type` then optional PDF white space then
  /// `/Page` ending on a valid PDF name-token boundary — end-of-input, PDF white
  /// space, or a PDF delimiter `()<>[]{}/%`. Any PDF *regular* character after
  /// `/Page` (a letter, digit, `_`, `-`, `#`, vertical tab, NBSP, etc.) means a
  /// different name (`/Pages`, `/PageMode`, `/PageLayout`, `/PageLabels`,
  /// `/Page_foo`, `/Page-foo`, `/Page#20foo`, …) and is rejected.
  static final RegExp _pageMarker = RegExp(
    '/Type[$_pdfWs]*/Page(?![^$_pdfWs()<>\\[\\]{}/%])',
  );

  /// Bytes carried between chunks so a marker split across a boundary is still
  /// detected. Comfortably exceeds the longest realistic marker.
  static const int _carryBytes = 64;

  @override
  Future<PdfHealthResult> inspect(String absolutePath) async {
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      absolutePath,
      followLinks: true,
    );
    if (type == FileSystemEntityType.notFound) {
      return const PdfHealthResult(status: PdfHealthStatus.missing);
    }
    if (type != FileSystemEntityType.file) {
      return const PdfHealthResult(status: PdfHealthStatus.unreadable);
    }

    if (p.extension(absolutePath).toLowerCase() != '.pdf') {
      return const PdfHealthResult(status: PdfHealthStatus.unknown);
    }

    final File file = File(absolutePath);
    int size;
    try {
      size = file.lengthSync();
    } on FileSystemException {
      return const PdfHealthResult(status: PdfHealthStatus.unreadable);
    }
    if (size < 0) {
      return const PdfHealthResult(status: PdfHealthStatus.unknown);
    }
    if (size == 0) {
      return const PdfHealthResult(
        status: PdfHealthStatus.corrupted,
        sizeBytes: 0,
      );
    }

    // Read the initial prefix and search for the header signature within it.
    final List<int> prefix;
    final RandomAccessFile raf;
    try {
      raf = file.openSync();
    } on FileSystemException {
      return PdfHealthResult(
        status: PdfHealthStatus.unreadable,
        sizeBytes: size,
      );
    }
    try {
      prefix = raf.readSync(_headerPrefixBytes);
    } on FileSystemException {
      return PdfHealthResult(
        status: PdfHealthStatus.unreadable,
        sizeBytes: size,
      );
    } finally {
      raf.closeSync();
    }

    if (_indexOfSignature(prefix) < 0) {
      return PdfHealthResult(
        status: PdfHealthStatus.corrupted,
        sizeBytes: size,
      );
    }

    final int? pageCount = size <= _pageCountSizeCapBytes
        ? _bestEffortPageCount(file)
        : null;

    return PdfHealthResult(
      status: PdfHealthStatus.healthy,
      sizeBytes: size,
      pageCount: pageCount,
    );
  }

  /// Index of the `%PDF-` signature within [data], or -1 when absent.
  int _indexOfSignature(List<int> data) {
    final int limit = data.length - _signature.length;
    for (int i = 0; i <= limit; i++) {
      bool match = true;
      for (int j = 0; j < _signature.length; j++) {
        if (data[i + j] != _signature[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  /// Best-effort, strict page count by streaming chunks and counting only
  /// genuine `/Type ... /Page` object markers (see [_pageMarker]).
  ///
  /// Memory-bounded: only one chunk plus a small carry is held. Two guards keep
  /// counting correct across chunk boundaries:
  /// 1. a global-offset guard so a marker re-seen via the carry is never
  ///    double-counted;
  /// 2. deferral of any match ending exactly at a non-final window's end — its
  ///    trailing boundary character may live in the next chunk (e.g. the `s` of
  ///    `/Pages`), so it is re-evaluated with full context via the carry, and a
  ///    final flush counts a genuine marker that ends at end-of-file.
  ///
  /// Returns `null` when no genuine page object is found.
  int? _bestEffortPageCount(File file) {
    RandomAccessFile raf;
    try {
      raf = file.openSync();
    } on FileSystemException {
      return null;
    }
    try {
      int count = 0;
      int base = 0; // Global offset of window[0].
      int lastCountedEnd = 0; // Global end of the last counted match.

      void scan(List<int> window, {required bool isFinal}) {
        final String text = String.fromCharCodes(window);
        for (final Match m in _pageMarker.allMatches(text)) {
          // Defer a match flush against the window end on non-final windows: the
          // boundary char may continue in the next chunk.
          if (!isFinal && m.end == window.length) continue;
          final int globalStart = base + m.start;
          if (globalStart >= lastCountedEnd) {
            count++;
            lastCountedEnd = base + m.end;
          }
        }
      }

      List<int> carry = const [];
      while (true) {
        final List<int> chunk = raf.readSync(chunkSize);
        if (chunk.isEmpty) break;
        final List<int> window = carry.isEmpty
            ? chunk
            : <int>[...carry, ...chunk];
        scan(window, isFinal: false);
        final int keep = window.length < _carryBytes
            ? window.length
            : _carryBytes;
        base += window.length - keep;
        carry = window.sublist(window.length - keep);
      }
      // Final flush: count a genuine marker ending at end-of-file.
      scan(carry, isFinal: true);
      return count > 0 ? count : null;
    } on FileSystemException {
      return null;
    } finally {
      raf.closeSync();
    }
  }
}
