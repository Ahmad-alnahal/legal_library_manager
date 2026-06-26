// lib/features/word_conversion/data/services/windows_microsoft_word_converter.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/entities/conversion_stage.dart';
import '../../domain/services/word_converter.dart';

/// Windows implementation of [WordConverter] using local Microsoft Word.
///
/// Drives Word through COM automation via a controlled PowerShell host. The
/// staged copy is opened read-only, macros are disabled, and PDF export uses
/// Word's native `ExportAsFixedFormat` path. Arguments are passed as a list
/// with `runInShell: false`; document paths are supplied through environment
/// variables rather than interpolated into the command line.
class WindowsMicrosoftWordConverter implements WordConverter {
  const WindowsMicrosoftWordConverter({
    this.timeout = const Duration(minutes: 2),
  });

  final Duration timeout;

  @override
  Future<WordConverterResult> convert({
    required String executablePath,
    required String stagedPath,
    required String outputPath,
    void Function(ConversionStage stage)? onStageChanged,
  }) async {
    try {
      onStageChanged?.call(ConversionStage.openingDocument);
      final generatedPdfPath = outputPath;
      final result = await _runPowerShell(
        executablePath,
        _conversionScript,
        {
          'MARJIY_WORD_INPUT': stagedPath,
          'MARJIY_WORD_OUTPUT': generatedPdfPath,
        },
        onStageMarker: (marker) {
          if (marker == 'exporting') {
            onStageChanged?.call(ConversionStage.exportingPdf);
          }
        },
      );

      if (result.exitCode != 0) {
        return const WordConverterFailed(
          error: WordConverterError.conversionFailed,
          safeMessage: 'Microsoft Word PDF export exited with an error status',
        );
      }
      return WordConverterOutput(generatedPdfPath: generatedPdfPath);
    } on ProcessException {
      return const WordConverterFailed(
        error: WordConverterError.processLaunchFailed,
        safeMessage: 'Microsoft Word automation host could not be launched',
      );
    } catch (_) {
      return const WordConverterFailed(
        error: WordConverterError.conversionFailed,
        safeMessage: 'unexpected error during the Word PDF export process',
      );
    }
  }

  Future<_ProcessResult> _runPowerShell(
    String hostExecutable,
    String script,
    Map<String, String> environment, {
    void Function(String marker)? onStageMarker,
  }) async {
    final process = await Process.start(
      hostExecutable,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        _encodePowerShell(script),
      ],
      environment: environment,
      runInShell: false,
    );

    // Stream stdout to intercept MARJIY_STAGE markers in real time.
    final stdoutLines = <String>[];
    final stdoutDone = Completer<void>();
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (onStageMarker != null && line.startsWith('MARJIY_STAGE:')) {
              onStageMarker(line.substring('MARJIY_STAGE:'.length));
            } else {
              stdoutLines.add(line);
            }
          },
          onDone: stdoutDone.complete,
          cancelOnError: true,
        );

    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();

    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigterm);
        return -1;
      },
    );

    await stdoutDone.future;

    return _ProcessResult(
      exitCode: exitCode,
      stdout: stdoutLines.join('\n'),
      stderr: await stderrFuture,
    );
  }

  static const String _conversionScript = r'''
$ErrorActionPreference = 'Stop'
$inputPath = $env:MARJIY_WORD_INPUT
$outputPath = $env:MARJIY_WORD_OUTPUT
$word = $null
$doc = $null
try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0
  $word.AutomationSecurity = 3
  $doc = $word.Documents.Open($inputPath, $false, $true, $false)
  Write-Output 'MARJIY_STAGE:exporting'
  [Console]::Out.Flush()
  $doc.ExportAsFixedFormat($outputPath, 17)
} finally {
  if ($null -ne $doc) {
    $doc.Close($false)
  }
  if ($null -ne $word) {
    $word.Quit()
  }
}
''';

  static String _encodePowerShell(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }
    return base64Encode(bytes);
  }
}

class _ProcessResult {
  const _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
