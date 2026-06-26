// lib/features/word_conversion/data/services/windows_microsoft_word_probe.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/services/microsoft_word_probe.dart';

/// Windows implementation of [MicrosoftWordProbe].
///
/// Uses local Microsoft Word COM automation through a controlled PowerShell
/// automation host. No document path is involved in probing. All process
/// arguments are passed as a list with `runInShell: false`, and failures are
/// mapped to [MicrosoftWordNotFound].
class WindowsMicrosoftWordProbe implements MicrosoftWordProbe {
  const WindowsMicrosoftWordProbe({
    this.hostExecutable = 'powershell.exe',
    this.timeout = const Duration(seconds: 20),
    this.versionProbe,
  });

  final String hostExecutable;
  final Duration timeout;
  final Future<String?> Function(String hostExecutable)? versionProbe;

  @override
  Future<MicrosoftWordProbeResult> probe() async {
    try {
      final version = await _probeVersion();
      if (version == null) return const MicrosoftWordNotFound();
      return MicrosoftWordFound(
        executablePath: hostExecutable,
        version: version,
      );
    } catch (_) {
      return const MicrosoftWordNotFound();
    }
  }

  Future<String?> _probeVersion() async {
    final override = versionProbe;
    if (override != null) return override(hostExecutable);

    const script = r'''
$ErrorActionPreference = 'Stop'
$word = $null
try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0
  Write-Output $word.Version
} finally {
  if ($null -ne $word) {
    $word.Quit()
  }
}
''';

    final result = await _runPowerShell(script, const {});
    if (result.exitCode != 0) return null;
    final output = result.stdout.trim();
    return output.isEmpty ? null : output.split(RegExp(r'\s+')).first;
  }

  Future<_ProcessResult> _runPowerShell(
    String script,
    Map<String, String> environment,
  ) async {
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

    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
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

    return _ProcessResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
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
