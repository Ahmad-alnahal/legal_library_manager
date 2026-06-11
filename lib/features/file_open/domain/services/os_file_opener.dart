// lib/features/file_open/domain/services/os_file_opener.dart

import '../entities/open_file_result.dart';

/// Outcome of a single OS-level open attempt.
sealed class OsOpenResult {
  const OsOpenResult();
}

/// The OS accepted the request without error.
final class OsOpenSuccess extends OsOpenResult {
  const OsOpenSuccess();
}

/// The OS rejected or could not fulfill the open request.
final class OsOpenFailed extends OsOpenResult {
  const OsOpenFailed({required this.code, required this.safeMessage});

  /// Stable error code for persistence and UI mapping.
  final FileOpenError code;

  /// Safe human-readable description. Never contains raw exception text,
  /// command strings, or document contents.
  final String safeMessage;
}

/// OS boundary for opening a validated, registered PDF file or its folder.
///
/// Implementations live in the data layer and may use [dart:io]. They must
/// never build a shell command string, request elevation, or modify the file.
abstract class OsFileOpener {
  const OsFileOpener();

  /// Opens [absolutePath] using the Windows default associated application.
  Future<OsOpenResult> openFile(String absolutePath);

  /// Opens the folder containing [absolutePath], selecting the file when the
  /// OS supports it.
  Future<OsOpenResult> openFolder(String absolutePath);
}
