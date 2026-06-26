// test/features/word_conversion/architecture/word_conversion_architecture_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards P1.1–P1.4 Clean Architecture boundaries and safety invariants:
///
/// - domain and application layers contain no dart:io, Drift, FFI, or Process;
/// - the Windows probe implementation lives in the data layer only;
/// - the probe uses an explicit argument list (no shell-string construction);
/// - `runInShell: true`, `cmd.exe`, and PowerShell are forbidden;
/// - no source-file or managed-copy mutation tokens appear in the probe;
/// - the use case depends only on the domain abstraction, not the concrete impl;
/// - staging filesystem (data) exposes no source-file mutation methods;
/// - staging filesystem uses the `.staging` sentinel suffix for temp files;
/// - StageWordSource (application) has no dart:io, Drift, or data-layer refs;
/// - StageWordSource never instantiates concrete data implementations directly.
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

  // ── Layer isolation: domain and application ──────────────────────────────

  group(
    'word_conversion domain and application layers are persistence-agnostic',
    () {
      const List<String> pureLayers = [
        'lib/features/word_conversion/domain',
        'lib/features/word_conversion/application',
      ];

      for (final dir in pureLayers) {
        test('$dir has no Drift imports', () {
          for (final file in dartFilesIn(dir)) {
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

        test('$dir has no dart:io imports', () {
          for (final file in dartFilesIn(dir)) {
            final src = read(file.path);
            expect(
              src.contains("import 'dart:io'") ||
                  src.contains('import "dart:io"'),
              isFalse,
              reason: '${file.path} must not import dart:io',
            );
          }
        });

        test('$dir has no Process invocations', () {
          for (final file in dartFilesIn(dir)) {
            final src = read(file.path);
            expect(
              RegExp(r'\bProcess\s*\.').hasMatch(src),
              isFalse,
              reason: '${file.path} must not invoke Process',
            );
          }
        });

        test('$dir has no dart:ffi, package:ffi, or package:win32 imports', () {
          for (final file in dartFilesIn(dir)) {
            final src = read(file.path);
            expect(
              src.contains('dart:ffi'),
              isFalse,
              reason: '${file.path} must not import dart:ffi',
            );
            expect(
              src.contains('package:ffi/'),
              isFalse,
              reason: '${file.path} must not import package:ffi',
            );
            expect(
              src.contains('package:win32/'),
              isFalse,
              reason: '${file.path} must not import package:win32',
            );
          }
        });
      }
    },
  );

  // ── Windows Microsoft Word probe: safe command invocation ────────────────

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

    test(
      'probe uses explicit argument list, not a concatenated shell string',
      () {
        expect(src.contains('Process.start'), isTrue);
        expect(src.contains('runInShell: false'), isTrue);
        expect(src.contains('-EncodedCommand'), isTrue);
      },
    );
  });

  // ── Domain probe abstraction: no OS dependencies ─────────────────────────

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

  // ── Use case: depends only on domain abstraction ─────────────────────────

  group('check_word_conversion_readiness.dart is abstraction-only', () {
    const String ucPath =
        'lib/features/word_conversion/application/check_word_conversion_readiness.dart';

    late String src;
    setUpAll(() => src = read(ucPath));

    test('use case accepts MicrosoftWordProbe through constructor', () {
      expect(src.contains('MicrosoftWordProbe'), isTrue);
    });

    test(
      'use case does not instantiate WindowsMicrosoftWordProbe directly',
      () {
        expect(src.contains('WindowsMicrosoftWordProbe'), isFalse);
      },
    );

    test('use case has no dart:io import', () {
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });

    test('use case has no Process invocation', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });

    test('use case does not reference the data layer', () {
      expect(src.contains('/data/'), isFalse);
    });
  });

  // ── P1.2: staging filesystem implementation (data layer) ─────────────────

  group('windows_word_staging_filesystem.dart safety', () {
    const String stagingFsPath =
        'lib/features/word_conversion/data/services/windows_word_staging_filesystem.dart';

    late String src;
    setUpAll(() => src = read(stagingFsPath));

    test('staging filesystem implementation exists in the data layer', () {
      expect(File(stagingFsPath).existsSync(), isTrue);
    });

    test('staging filesystem does not delete source files directly', () {
      // deleteTempSafe may delete staging temp files only; the method that
      // receives a sourcePath never has a delete/rename call on it.
      // We verify the overall file has no broad mutation calls that could
      // reach arbitrary paths.
      for (final token in ['.deleteSync(', '.renameSync(', '.writeAsString(']) {
        expect(
          src.contains(token),
          isFalse,
          reason:
              'windows_word_staging_filesystem.dart must not use $token (could reach source paths)',
        );
      }
    });

    test('staging filesystem uses .staging sentinel suffix for temp files', () {
      expect(
        src.contains('.staging'),
        isTrue,
        reason:
            'temp files must carry the .staging suffix so recovery cleanup is safe',
      );
    });

    test('staging filesystem does not use runInShell: true', () {
      expect(src.contains('runInShell: true'), isFalse);
    });
  });

  // ── P1.2: StageWordSource use case isolation ──────────────────────────────

  group('stage_word_source.dart is abstraction-only', () {
    const String stagePath =
        'lib/features/word_conversion/application/stage_word_source.dart';

    late String src;
    setUpAll(() => src = read(stagePath));

    test('stage_word_source.dart file exists in application layer', () {
      expect(File(stagePath).existsSync(), isTrue);
    });

    test('use case has no dart:io import', () {
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });

    test('use case has no Drift import', () {
      expect(src.contains('package:drift/'), isFalse);
      expect(src.contains('core/database'), isFalse);
    });

    test('use case has no Process invocation', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });

    test('use case does not reference the data layer', () {
      expect(src.contains('/data/'), isFalse);
    });

    test(
      'use case does not instantiate WindowsWordStagingFilesystem directly',
      () {
        expect(src.contains('WindowsWordStagingFilesystem'), isFalse);
      },
    );

    test(
      'use case does not instantiate DriftWordConversionRepository directly',
      () {
        expect(src.contains('DriftWordConversionRepository'), isFalse);
      },
    );
  });

  // ── P1.2: word_staging_filesystem.dart domain abstraction ─────────────────

  group('word_staging_filesystem.dart domain interface is OS-agnostic', () {
    const String domainFsPath =
        'lib/features/word_conversion/domain/services/word_staging_filesystem.dart';

    late String src;
    setUpAll(() => src = read(domainFsPath));

    test('domain staging filesystem has no dart:io import', () {
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });

    test('domain staging filesystem has no Process invocation', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });
  });

  // ── P1.3: WindowsMicrosoftWordConverter safe process invocation ──────────

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

  // ── P1.3: WordConverter domain interface is OS-agnostic ──────────────────

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

  // ── P1.3: WordOutputFilesystem domain interface is OS-agnostic ───────────

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

  // ── P1.3: ConvertStagedWordSource use case isolation ─────────────────────

  group('convert_staged_word_source.dart is abstraction-only', () {
    const String convertPath =
        'lib/features/word_conversion/application/convert_staged_word_source.dart';

    late String src;
    setUpAll(() => src = read(convertPath));

    test('convert_staged_word_source.dart exists in application layer', () {
      expect(File(convertPath).existsSync(), isTrue);
    });

    test('use case has no dart:io import', () {
      expect(
        src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
        isFalse,
      );
    });

    test('use case has no Drift import', () {
      expect(src.contains('package:drift/'), isFalse);
      expect(src.contains('core/database'), isFalse);
    });

    test('use case has no Process invocation', () {
      expect(RegExp(r'\bProcess\s*\.').hasMatch(src), isFalse);
    });

    test('use case does not reference the data layer', () {
      expect(src.contains('/data/'), isFalse);
    });

    test(
      'use case does not instantiate WindowsMicrosoftWordConverter directly',
      () {
        expect(src.contains('WindowsMicrosoftWordConverter'), isFalse);
      },
    );

    test(
      'use case does not instantiate WindowsWordOutputFilesystem directly',
      () {
        expect(src.contains('WindowsWordOutputFilesystem'), isFalse);
      },
    );

    test(
      'use case does not instantiate DriftWordConversionRepository directly',
      () {
        expect(src.contains('DriftWordConversionRepository'), isFalse);
      },
    );
  });

  // ── P1.3: WindowsWordOutputFilesystem data layer safety ──────────────────

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

  // ── P1.4: Review use cases are abstraction-only ───────────────────────────

  group('P1.4 review use cases are abstraction-only', () {
    const List<String> reviewUseCases = [
      'lib/features/word_conversion/application/load_conversion_review_queue.dart',
      'lib/features/word_conversion/application/approve_conversion_quality.dart',
      'lib/features/word_conversion/application/reject_conversion_quality.dart',
    ];

    for (final path in reviewUseCases) {
      test('$path exists in application layer', () {
        expect(File(path).existsSync(), isTrue);
      });

      test('$path has no dart:io import', () {
        final src = read(path);
        expect(
          src.contains("import 'dart:io'") || src.contains('import "dart:io"'),
          isFalse,
          reason: '$path must not import dart:io',
        );
      });

      test('$path has no Drift import', () {
        final src = read(path);
        expect(
          src.contains('package:drift/'),
          isFalse,
          reason: '$path must not import Drift',
        );
        expect(
          src.contains('core/database'),
          isFalse,
          reason: '$path must not import the database layer',
        );
      });

      test('$path does not reference the data layer', () {
        final src = read(path);
        expect(
          src.contains('/data/'),
          isFalse,
          reason: '$path must not import from the data layer',
        );
      });

      test(
        '$path does not instantiate DriftWordConversionRepository directly',
        () {
          final src = read(path);
          expect(src.contains('DriftWordConversionRepository'), isFalse);
        },
      );
    }
  });

  // ── P1.4: Approve/Reject never delete files ───────────────────────────────

  group(
    'approve_conversion_quality and reject_conversion_quality do not delete files',
    () {
      const List<String> decisionUseCases = [
        'lib/features/word_conversion/application/approve_conversion_quality.dart',
        'lib/features/word_conversion/application/reject_conversion_quality.dart',
      ];

      const List<String> fileMutationTokens = [
        '.delete(',
        '.deleteSync(',
        '.rename(',
        '.renameSync(',
        '.writeAs',
        '.openWrite(',
        'copySync(',
        '.copy(',
        'File(',
        "import 'dart:io'",
      ];

      for (final path in decisionUseCases) {
        test('$path has no file mutation calls', () {
          final src = read(path);
          for (final token in fileMutationTokens) {
            expect(
              src.contains(token),
              isFalse,
              reason:
                  '$path must not contain $token — reject must never delete files',
            );
          }
        });
      }
    },
  );

  // ── Progress honesty: no fake percentage progress ────────────────────────

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
      // No numeric literal that looks like a percentage target
      expect(
        RegExp(r'\b(25|35|50|70|75|90|100)\s*[/%]').hasMatch(src),
        isFalse,
        reason: 'ConversionStage must not contain hardcoded percentage values',
      );
    });

    test('ConvertStagedWordSource has no hardcoded percentage literals', () {
      const convertPath =
          'lib/features/word_conversion/application/convert_staged_word_source.dart';
      final src = read(convertPath);
      for (final token in percentageForbiddenTokens) {
        expect(
          src.contains(token),
          isFalse,
          reason: 'ConvertStagedWordSource must not fake percentage: $token',
        );
      }
    });
  });
}
