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
