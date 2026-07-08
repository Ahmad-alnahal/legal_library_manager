// test/features/file_open/data/services/windows_os_file_opener_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/file_open/data/services/explorer_process_launcher.dart';
import 'package:legal_library_manager/features/file_open/data/services/windows_os_file_opener.dart';
import 'package:legal_library_manager/features/file_open/domain/services/os_file_opener.dart';

class _FakeExplorerProcessLauncher implements ExplorerProcessLauncher {
  String? capturedExecutable;
  List<String>? capturedArguments;
  Object? throwOn;

  @override
  Future<void> start(String executable, List<String> arguments) async {
    if (throwOn != null) throw throwOn!;
    capturedExecutable = executable;
    capturedArguments = arguments;
  }
}

void main() {
  group('WindowsOsFileOpener.openFolder — parent-directory navigation', () {
    // `/select,<path>` is unreliable in practice: when Explorer reuses an
    // existing process, the /select request can be silently dropped and
    // Explorer falls back to its configured home location (Documents) while
    // still exiting 0. Passing the exact parent directory as a plain argument
    // is the reliable primitive Explorer always honors.

    test('opens the exact parent directory, not /select,<path>', () async {
      final launcher = _FakeExplorerProcessLauncher();
      final opener = WindowsOsFileOpener(processLauncher: launcher);

      final result = await opener.openFolder(r'C:\Sources\report.pdf');

      expect(result, isA<OsOpenSuccess>());
      expect(launcher.capturedExecutable, 'explorer.exe');
      expect(launcher.capturedArguments, [r'C:\Sources']);
      expect(
        launcher.capturedArguments!.any((a) => a.contains('/select')),
        isFalse,
      );
    });

    test('handles a path containing spaces', () async {
      final launcher = _FakeExplorerProcessLauncher();
      final opener = WindowsOsFileOpener(processLauncher: launcher);

      await opener.openFolder(r'C:\My Documents\legal report.pdf');

      expect(launcher.capturedArguments, [r'C:\My Documents']);
      expect(launcher.capturedArguments!.single.contains('"'), isFalse);
    });

    test('handles an Arabic absolute path', () async {
      final launcher = _FakeExplorerProcessLauncher();
      final opener = WindowsOsFileOpener(processLauncher: launcher);

      await opener.openFolder(r'C:\المستندات\تقرير قانوني.pdf');

      expect(launcher.capturedArguments, [r'C:\المستندات']);
    });

    test('handles a nested Arabic path with spaces', () async {
      final launcher = _FakeExplorerProcessLauncher();
      final opener = WindowsOsFileOpener(processLauncher: launcher);

      await opener.openFolder(r'C:\المكتبة المدارة\قسم أول\تقرير قانوني.pdf');

      expect(launcher.capturedArguments, [r'C:\المكتبة المدارة\قسم أول']);
    });

    test('handles a file directly under a drive root', () async {
      final launcher = _FakeExplorerProcessLauncher();
      final opener = WindowsOsFileOpener(processLauncher: launcher);

      await opener.openFolder(r'C:\report.pdf');

      expect(launcher.capturedArguments, [r'C:\']);
    });

    test('returns OsOpenFailed when the launcher throws', () async {
      final launcher = _FakeExplorerProcessLauncher()
        ..throwOn = Exception('boom');
      final opener = WindowsOsFileOpener(processLauncher: launcher);

      final result = await opener.openFolder(r'C:\Sources\report.pdf');

      expect(result, isA<OsOpenFailed>());
    });
  });
}
