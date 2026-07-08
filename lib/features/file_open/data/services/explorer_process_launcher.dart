// lib/features/file_open/data/services/explorer_process_launcher.dart

import 'dart:io';

/// Thin boundary around starting a detached OS process for folder reveal.
///
/// Injected into [WindowsOsFileOpener] so Explorer argument construction can
/// be unit-tested without spawning a real process.
abstract class ExplorerProcessLauncher {
  const ExplorerProcessLauncher();

  Future<void> start(String executable, List<String> arguments);
}

/// Default [ExplorerProcessLauncher], backed by [Process.start] with
/// `runInShell: false`.
class IoExplorerProcessLauncher implements ExplorerProcessLauncher {
  const IoExplorerProcessLauncher();

  @override
  Future<void> start(String executable, List<String> arguments) =>
      Process.start(executable, arguments, runInShell: false);
}
