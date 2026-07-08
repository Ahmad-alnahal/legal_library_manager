// test/features/word_conversion/architecture/word_conversion_architecture_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the remaining P1 Word conversion infrastructure.
///
/// The retired staging/review workflow is intentionally not covered here:
/// conversion now happens only inside managed copy, while these lower-level
/// services remain reusable boundaries for Microsoft Word automation.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> dartFilesIn(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }

  group('word_conversion domain layer is persistence-agnostic', () {
    const String domainDir = 'lib/features/word_conversion/domain';

    test('domain has no Drift imports', () {
      for (final file in dartFilesIn(domainDir)) {
        final src = read(file.path);
        expect(
          src.contains('package:drift/'),
          isFalse,
          reason: '${file.path} must not import Drift',
        );
        expect(
          src.contains('core/database'),
          isFalse,
          reason: '${file.path} must not import the database layer',
        );
      }
    });

    test('domain has no dart:io imports', () {
      for (final file in dartFilesIn(domainDir)) {
        final src = read(file.path);
        expect(
          src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
          isFalse,
          reason: '${file.path} must not import dart:io',
        );
      }
    });

    test('domain has no Process invocations', () {
      for (final file in dartFilesIn(domainDir)) {
        final src = read(file.path);
        expect(
          RegExp(r'\bProcess\s*\.').hasMatch(src),
          isFalse,
          reason: '${file.path} must not invoke Process',
        );
      }
    });

    test('domain has no FFI or win32 imports', () {
      for (final file in dartFilesIn(domainDir)) {
        final src = read(file.path);
        expect(src.contains('dart:ffi'), isFalse);
        expect(src.contains('package:ffi/'), isFalse);
        expect(src.contains('package:win32/'), isFalse);
      }
    });
  });

  group('windows_microsoft_word_probe.dart safety', () {
    const String probePath =
        'lib/features/word_conversion/data/services/windows_microsoft_word_probe.dart';

    late String src;
    setUpAll(() => src = read(probePath));

    test('probe implementation exists in the data layer', () {
      expect(File(probePath).existsSync(), isTrue);
    });

    test('probe does not use runInShell: true', () {
      expect(
        src.contains('runInShell: true'),
        isFalse,
        reason: 'Process must never be invoked through a shell',
      );
    });

    test('probe does not use cmd.exe', () {
      expect(src.toLowerCase().contains('cmd.exe'), isFalse);
    });

    test('probe does not mutate any files', () {
      for (final token in [
        '.delete(',
        '.deleteSync(',
        '.rename(',
        '.renameSync(',
        '.writeAs',
        '.openWrite(',
        'copySync(',
        '.copy(',
        '.create(',
        'createSync(',
        'truncate(',
      ]) {
        expect(
          src.contains(token),
          isFalse,
          reason: 'windows_microsoft_word_probe.dart must not contain $token',
        );
      }
    });

    test('probe uses explicit argument list', () {
      expect(src.contains('Process.start'), isTrue);
      expect(src.contains('runInShell: false'), isTrue);
      expect(src.contains('-EncodedCommand'), isTrue);
    });
  });

  group('microsoft_word_probe.dart domain interface is OS-agnostic', () {
    const String domainPath =
        'lib/features/word_conversion/domain/services/microsoft_word_probe.dart';

    late String src;
    setUpAll(() => src = read(domainPath));

    test('domain probe has no dart:io import', () {
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });

    test('domain probe has no Process invocation', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });
  });

  group('windows_microsoft_word_converter.dart safety', () {
    const String converterPath =
        'lib/features/word_conversion/data/services/windows_microsoft_word_converter.dart';

    late String src;
    setUpAll(() => src = read(converterPath));

    test('converter implementation exists in the data layer', () {
      expect(File(converterPath).existsSync(), isTrue);
    });

    test('converter does not use runInShell: true', () {
      expect(
        src.contains('runInShell: true'),
        isFalse,
        reason: 'Process must never be invoked through a shell',
      );
    });

    test('converter explicitly passes runInShell: false', () {
      expect(
        src.contains('runInShell: false'),
        isTrue,
        reason: 'Safe process invocation requires explicit runInShell: false',
      );
    });

    test('converter does not reference cmd.exe', () {
      expect(src.toLowerCase().contains('cmd.exe'), isFalse);
    });

    test('converter disables macros and opens staged source read-only', () {
      expect(
        src.contains('AutomationSecurity = 3'),
        isTrue,
        reason: 'Word automation must force-disable macros',
      );
      expect(
        src.contains(r'$word.Documents.Open($inputPath, $false, $true'),
        isTrue,
      );
    });

    test('converter uses Microsoft Word native PDF export', () {
      expect(
        src.contains('ExportAsFixedFormat'),
        isTrue,
        reason: 'Conversion must use Word native PDF export for fidelity',
      );
      expect(src.contains('17'), isTrue);
    });

    test('converter passes document paths through environment variables', () {
      expect(src.contains('MARJIY_WORD_INPUT'), isTrue);
      expect(src.contains('MARJIY_WORD_OUTPUT'), isTrue);
    });

    test('converter does not delete, rename, or write any files', () {
      for (final token in [
        '.delete(',
        '.deleteSync(',
        '.rename(',
        '.renameSync(',
        '.writeAs',
        '.openWrite(',
        'copySync(',
        '.create(',
      ]) {
        expect(
          src.contains(token),
          isFalse,
          reason:
              'windows_microsoft_word_converter.dart must not contain $token',
        );
      }
    });

    // ── QA follow-up: Protected View fallback + diagnostic markers ─────────

    test('converter falls back to ProtectedViewWindows when Open fails', () {
      expect(
        src.contains('ProtectedViewWindows.Open'),
        isTrue,
        reason:
            'a Protected View fallback must be attempted when the normal '
            'Documents.Open call fails',
      );
      expect(
        src.contains('.Edit()'),
        isTrue,
        reason:
            'the protected-view window must be edited out of protected '
            'view to obtain a real, exportable Document object',
      );
    });

    test('protected view fallback only touches the staged temp path', () {
      // The fallback must reuse the same $inputPath variable used by the
      // normal Documents.Open call — never the original source path, which
      // this converter never receives (only the app-owned staged copy).
      expect(src.contains('ProtectedViewWindows.Open(\$inputPath)'), isTrue);
    });

    test('converter emits stage-specific safe diagnostic markers', () {
      for (final marker in [
        'MARJIY_ERROR:document_open_failed:',
        'MARJIY_ERROR:protected_view_edit_failed:',
        'MARJIY_ERROR:export_failed:',
        'MARJIY_ERROR:blank_export_failed:',
      ]) {
        expect(
          src.contains(marker),
          isTrue,
          reason: 'converter must emit the $marker diagnostic marker',
        );
      }
    });

    test('diagnostic markers carry only a numeric HResult, never raw text', () {
      expect(src.contains(r'$($_.Exception.HResult)'), isTrue);
      // No raw exception message property is ever written to output.
      expect(src.contains(r'.Exception.Message'), isFalse);
      expect(src.contains(r'.ToString()'), isFalse);
    });

    test('_extractDiagnostic never surfaces raw stderr text', () {
      expect(src.contains('result.stderr'), isFalse);
    });

    test('convertBlankDocument creates a throwaway document and never opens '
        'a user file', () {
      expect(src.contains('convertBlankDocument'), isTrue);
      expect(
        src.contains('Documents.Add()'),
        isTrue,
        reason: 'blank-document diagnostic must not open any input file',
      );
      expect(
        src.contains('MARJIY_WORD_INPUT'),
        isTrue,
        reason:
            'MARJIY_WORD_INPUT must still exist for the real conversion '
            'path even though the blank-document script never reads it',
      );
    });

    test('exit codes distinguish every failure stage', () {
      // 2 = document_open_failed, 3 = export_failed,
      // 4 = protected_view_edit_failed, 5 = blank_export_failed.
      for (final exitCode in ['exit 2', 'exit 3', 'exit 4', 'exit 5']) {
        expect(
          src.contains(exitCode),
          isTrue,
          reason: 'missing distinct $exitCode for a diagnosable failure stage',
        );
      }
    });
  });

  group('word_converter.dart domain interface is OS-agnostic', () {
    const String domainConverterPath =
        'lib/features/word_conversion/domain/services/word_converter.dart';

    late String src;
    setUpAll(() => src = read(domainConverterPath));

    test('domain converter has no dart:io import', () {
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });

    test('domain converter has no Process invocation', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });
  });

  group('word_output_filesystem.dart domain interface is OS-agnostic', () {
    const String domainOutputFsPath =
        'lib/features/word_conversion/domain/services/word_output_filesystem.dart';

    late String src;
    setUpAll(() => src = read(domainOutputFsPath));

    test('domain output filesystem has no dart:io import', () {
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });

    test('domain output filesystem has no Process invocation', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });
  });

  group('windows_word_output_filesystem.dart safety', () {
    const String outputFsPath =
        'lib/features/word_conversion/data/services/windows_word_output_filesystem.dart';

    late String src;
    setUpAll(() => src = read(outputFsPath));

    test('output filesystem implementation exists in the data layer', () {
      expect(File(outputFsPath).existsSync(), isTrue);
    });

    test('output filesystem does not use runInShell: true', () {
      expect(src.contains('runInShell: true'), isFalse);
    });

    test('output filesystem does not invoke any Process', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });
  });

  // ── Bug 1: no network/cloud dependency for .doc conversion ────────────────
  //
  // Conversion must use local Microsoft Word COM automation only. No http
  // client, raw sockets, or web/cloud endpoints may be reachable from any
  // word_conversion or managed_copy data service.

  group('word_conversion and managed_copy data services have no network I/O', () {
    const List<String> networkFreeDirs = [
      'lib/features/word_conversion/data',
      'lib/features/managed_copy/data',
    ];

    const List<String> forbiddenNetworkTokens = [
      "import 'package:http/",
      'import "package:http/',
      'HttpClient(',
      'Uri.http(',
      'Uri.https(',
      'WebSocket',
      'dart:io show Socket',
      'RawSocket',
      "Socket.connect",
    ];

    for (final dir in networkFreeDirs) {
      test('$dir contains no http/socket/cloud tokens', () {
        for (final file in dartFilesIn(dir)) {
          final src = read(file.path);
          for (final token in forbiddenNetworkTokens) {
            expect(
              src.contains(token),
              isFalse,
              reason: '${file.path} must not contain network token: $token',
            );
          }
        }
      });
    }

    test('windows_microsoft_word_converter.dart drives local Word COM only', () {
      const converterPath =
          'lib/features/word_conversion/data/services/windows_microsoft_word_converter.dart';
      final src = read(converterPath);
      expect(
        src.contains('Word.Application'),
        isTrue,
        reason:
            'Conversion must automate the local Word.Application COM object',
      );
      expect(src.contains('runInShell: false'), isTrue);
      expect(src.contains('runInShell: true'), isFalse);
    });

    test('windows_microsoft_word_probe.dart probes local Word COM only', () {
      const probePath =
          'lib/features/word_conversion/data/services/windows_microsoft_word_probe.dart';
      final src = read(probePath);
      expect(
        src.contains('Word.Application'),
        isTrue,
        reason: 'Probe must check the local Word.Application COM object',
      );
      expect(src.contains('runInShell: false'), isTrue);
      expect(src.contains('runInShell: true'), isFalse);
    });

    test('managed_copy_word_converter.dart has no network tokens', () {
      const path =
          'lib/features/managed_copy/data/services/managed_copy_word_converter.dart';
      final src = read(path);
      for (final token in forbiddenNetworkTokens) {
        expect(src.contains(token), isFalse);
      }
    });
  });

  group('no fake percentage progress in word_conversion feature', () {
    const List<String> percentageForbiddenTokens = [
      'progressPercent',
      'percentComplete',
      'progressFraction',
      'fakePercent',
      'hardcodedPercent',
    ];

    test('ConversionStage enum has no percentage-like members', () {
      const stagePath =
          'lib/features/word_conversion/domain/entities/conversion_stage.dart';
      final src = read(stagePath);
      for (final token in percentageForbiddenTokens) {
        expect(
          src.contains(token),
          isFalse,
          reason: 'ConversionStage must not contain percentage token: $token',
        );
      }
      expect(
        RegExp(r'\b(25|35|50|70|75|90|100)\s*[/%]').hasMatch(src),
        isFalse,
        reason: 'ConversionStage must not contain hardcoded percentage values',
      );
    });
  });
}
