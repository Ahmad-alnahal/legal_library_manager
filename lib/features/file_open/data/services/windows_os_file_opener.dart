// lib/features/file_open/data/services/windows_os_file_opener.dart

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../domain/entities/open_file_result.dart';
import '../../domain/services/os_file_opener.dart';
import 'explorer_process_launcher.dart';

/// Windows-specific [OsFileOpener].
///
/// For [openFile]: calls [ShellExecuteEx] directly with verb `open` and no
/// shell involvement. ShellExecuteEx is a synchronous Win32 dispatch that
/// returns success/failure at the time of dispatch. This is the only reliable
/// way to detect errors such as no registered association or access denied,
/// which are invisible when launching explorer.exe (it forks and always exits 0).
///
/// For [openFolder]: launches explorer.exe with the file's parent directory
/// as its only argument, via [Process.start] with [runInShell] = false.
/// Folder-open is fire-and-forget; the result is not reported by explorer.exe
/// and success is assumed when the process starts.
///
/// Safety invariants enforced:
/// - No shell interpreter or shell built-in command is used.
/// - File path is passed as a separate FFI pointer, never concatenated into a
///   command string.
/// - Verb is always `open`; no `runas` or any elevation verb is used.
/// - No elevation is requested.
/// - The registered file is never modified, copied, moved, renamed, or deleted.
class WindowsOsFileOpener implements OsFileOpener {
  const WindowsOsFileOpener({
    this.processLauncher = const IoExplorerProcessLauncher(),
  });

  /// Injectable so Explorer argument construction can be unit-tested without
  /// spawning a real process.
  final ExplorerProcessLauncher processLauncher;

  static const String _explorer = 'explorer.exe';

  // SEE_MASK_FLAG_NO_UI (0x400): suppress all system-generated error dialogs
  // so failures are returned as error codes rather than shown as UI prompts.
  static const int _seeMaskFlagNoUi = 0x00000400;

  @override
  Future<OsOpenResult> openFile(String absolutePath) async {
    try {
      final result = using<OsOpenResult>((arena) {
        final sei = arena<SHELLEXECUTEINFO>();
        sei.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
        sei.ref.fMask = _seeMaskFlagNoUi;
        sei.ref.lpVerb = 'open'.toNativeUtf16(allocator: arena);
        sei.ref.lpFile = absolutePath.toNativeUtf16(allocator: arena);
        sei.ref.nShow = 1; // SW_SHOWNORMAL

        final success = ShellExecuteEx(sei);
        if (success == 0) {
          final errorCode = GetLastError();
          final code = _classifyShellError(errorCode);
          return OsOpenFailed(code: code, safeMessage: _safeMessage(code));
        }
        return const OsOpenSuccess();
      });
      return result;
    } catch (_) {
      return const OsOpenFailed(
        code: FileOpenError.osLaunchFailed,
        safeMessage: 'Failed to launch the associated application.',
      );
    }
  }

  @override
  Future<OsOpenResult> openFolder(String absolutePath) {
    // `explorer.exe /select,<path>` is unreliable in practice: when Explorer
    // reuses an existing process (single-instance IPC), the /select request
    // can silently be dropped and Explorer falls back to its configured home
    // location (typically Documents) while still exiting 0 — a launch
    // "succeeds" but reveals the wrong folder with no way to detect the
    // mismatch from the exit code alone. Opening the exact parent folder
    // directly (no /select switch) is the reliable primitive: Explorer always
    // navigates to a directory argument it is given.
    final String parentFolder = _parentDirectory(absolutePath);
    return _launchExplorer([parentFolder]);
  }

  /// Returns the parent directory of an absolute Windows file path using
  /// plain string manipulation (no dart:path dependency).
  static String _parentDirectory(String absolutePath) {
    final String normalized = absolutePath.replaceAll('/', r'\');
    final int lastSeparator = normalized.lastIndexOf(r'\');
    if (lastSeparator <= 2) {
      // Drive root, e.g. `C:\file.pdf` -> `C:\`.
      return normalized.substring(0, lastSeparator + 1);
    }
    return normalized.substring(0, lastSeparator);
  }

  Future<OsOpenResult> _launchExplorer(List<String> arguments) async {
    try {
      await processLauncher.start(_explorer, arguments);
      return const OsOpenSuccess();
    } on ProcessException catch (e) {
      final code = _classifyProcessError(e.errorCode);
      return OsOpenFailed(code: code, safeMessage: _safeMessage(code));
    } on FileSystemException catch (e) {
      final code = _classifyFileSystemError(e.message);
      return OsOpenFailed(code: code, safeMessage: _safeMessage(code));
    } catch (_) {
      return const OsOpenFailed(
        code: FileOpenError.osLaunchFailed,
        safeMessage: 'Failed to launch the associated application.',
      );
    }
  }

  // Win32 error codes from GetLastError() after ShellExecuteEx returns 0:
  //    2 = ERROR_FILE_NOT_FOUND
  //    3 = ERROR_PATH_NOT_FOUND
  //    5 = ERROR_ACCESS_DENIED
  //   31 = SE_ERR_NOASSOC
  // 1155 = ERROR_NO_ASSOCIATION (SE_ERR_NOASSOC)
  FileOpenError _classifyShellError(int errorCode) {
    return switch (errorCode) {
      2 || 3 => FileOpenError.pathNotFound,
      5 => FileOpenError.permissionDenied,
      31 || 1155 => FileOpenError.noAssociatedApplication,
      _ => FileOpenError.osLaunchFailed,
    };
  }

  FileOpenError _classifyProcessError(int errorCode) {
    if (errorCode == 5) return FileOpenError.permissionDenied;
    if (errorCode == 1155 || errorCode == 1156) {
      return FileOpenError.noAssociatedApplication;
    }
    return FileOpenError.osLaunchFailed;
  }

  FileOpenError _classifyFileSystemError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('access') ||
        lower.contains('denied') ||
        lower.contains('permission')) {
      return FileOpenError.permissionDenied;
    }
    return FileOpenError.osLaunchFailed;
  }

  String _safeMessage(FileOpenError code) => switch (code) {
    FileOpenError.permissionDenied =>
      'Access denied when launching the application.',
    FileOpenError.noAssociatedApplication =>
      'No application is registered for this file type.',
    FileOpenError.pathNotFound =>
      'Stored path does not exist on the filesystem.',
    _ => 'Failed to launch the associated application.',
  };
}
