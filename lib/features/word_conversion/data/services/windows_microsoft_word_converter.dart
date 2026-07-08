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
        final diagnostic = _extractDiagnostic(result.stdout);
        return WordConverterFailed(
          error: WordConverterError.conversionFailed,
          safeMessage: diagnostic == null
              ? 'Microsoft Word PDF export exited with an error status '
                    '(exit code ${result.exitCode})'
              : 'Microsoft Word PDF export failed while $diagnostic '
                    '(exit code ${result.exitCode})',
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

  @override
  Future<WordConverterResult> convertBlankDocument({
    required String executablePath,
    required String outputPath,
  }) async {
    try {
      final result = await _runPowerShell(
        executablePath,
        _blankDocumentScript,
        {'MARJIY_WORD_OUTPUT': outputPath},
      );

      if (result.exitCode != 0) {
        final diagnostic = _extractDiagnostic(result.stdout);
        return WordConverterFailed(
          error: WordConverterError.conversionFailed,
          safeMessage: diagnostic == null
              ? 'Microsoft Word blank-document export exited with an error '
                    'status (exit code ${result.exitCode})'
              : 'Microsoft Word blank-document export failed while '
                    '$diagnostic (exit code ${result.exitCode})',
        );
      }
      return WordConverterOutput(generatedPdfPath: outputPath);
    } on ProcessException {
      return const WordConverterFailed(
        error: WordConverterError.processLaunchFailed,
        safeMessage: 'Microsoft Word automation host could not be launched',
      );
    } catch (_) {
      return const WordConverterFailed(
        error: WordConverterError.conversionFailed,
        safeMessage:
            'unexpected error during the Word blank-document export process',
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
  try {
    $doc = $word.Documents.Open($inputPath, $false, $true, $false)
  } catch {
    # Normal open failed — the file may be flagged for Protected View
    # (Mark of the Web) even after staging. Fall back to explicitly opening
    # it as a protected-view window and editing out of protected view, which
    # is the only supported way to obtain a real, exportable Document object
    # for such a file via automation. Only the temp staged copy is ever
    # touched here — never the original source.
    $pvWindow = $null
    try {
      $pvWindow = $word.ProtectedViewWindows.Open($inputPath)
    } catch {
      Write-Output "MARJIY_ERROR:document_open_failed:$($_.Exception.HResult)"
      exit 2
    }
    try {
      $doc = $pvWindow.Edit()
    } catch {
      Write-Output "MARJIY_ERROR:protected_view_edit_failed:$($_.Exception.HResult)"
      exit 4
    }
  }
  if ($null -eq $doc) {
    Write-Output 'MARJIY_ERROR:document_open_failed:0'
    exit 2
  }
  Write-Output 'MARJIY_STAGE:exporting'
  [Console]::Out.Flush()
  try {
    $doc.ExportAsFixedFormat($outputPath, 17)
  } catch {
    Write-Output "MARJIY_ERROR:export_failed:$($_.Exception.HResult)"
    exit 3
  }
} finally {
  if ($null -ne $doc) {
    $doc.Close($false)
  }
  if ($null -ne $word) {
    $word.Quit()
  }
}
''';

  /// Creates a throwaway blank document and exports it — no input file is
  /// ever opened, so this isolates Word's own launch/export capability from
  /// any specific document's content or trust state.
  static const String _blankDocumentScript = r'''
$ErrorActionPreference = 'Stop'
$outputPath = $env:MARJIY_WORD_OUTPUT
$word = $null
$doc = $null
try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0
  $word.AutomationSecurity = 3
  try {
    $doc = $word.Documents.Add()
  } catch {
    Write-Output "MARJIY_ERROR:document_open_failed:$($_.Exception.HResult)"
    exit 2
  }
  try {
    $doc.ExportAsFixedFormat($outputPath, 17)
  } catch {
    Write-Output "MARJIY_ERROR:blank_export_failed:$($_.Exception.HResult)"
    exit 5
  }
} finally {
  if ($null -ne $doc) {
    $doc.Close($false)
  }
  if ($null -ne $word) {
    $word.Quit()
  }
}
''';

  /// Parses a sanitized diagnostic phrase from an `MARJIY_ERROR:` marker line
  /// in [stdout], or null when no such marker was emitted. Only a stable
  /// English stage label and a numeric Windows COM HRESULT are surfaced —
  /// never raw exception text, document content, or file paths.
  static String? _extractDiagnostic(String stdout) {
    for (final line in const LineSplitter().convert(stdout)) {
      if (line.startsWith('MARJIY_ERROR:document_open_failed:')) {
        final code = line.substring(
          'MARJIY_ERROR:document_open_failed:'.length,
        );
        return 'opening the document (HRESULT $code) — Word may be treating '
            'the file as untrusted (Protected View) or require online '
            'activation';
      }
      if (line.startsWith('MARJIY_ERROR:protected_view_edit_failed:')) {
        final code = line.substring(
          'MARJIY_ERROR:protected_view_edit_failed:'.length,
        );
        return 'editing the document out of Protected View (HRESULT $code)';
      }
      if (line.startsWith('MARJIY_ERROR:export_failed:')) {
        final code = line.substring('MARJIY_ERROR:export_failed:'.length);
        return 'exporting the PDF (HRESULT $code)';
      }
      if (line.startsWith('MARJIY_ERROR:blank_export_failed:')) {
        final code = line.substring('MARJIY_ERROR:blank_export_failed:'.length);
        return 'exporting a blank diagnostic PDF (HRESULT $code)';
      }
    }
    return null;
  }

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
