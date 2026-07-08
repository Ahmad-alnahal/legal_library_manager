// lib/features/managed_copy/data/services/win32_local_file_availability_checker.dart

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../domain/services/local_file_availability_checker.dart';

/// Win32-backed [LocalFileAvailabilityChecker].
///
/// Uses `GetFileAttributesW` to detect the file attribute bits that Windows
/// cloud-sync clients (OneDrive Files On-Demand and similar) set on
/// "online-only" placeholder files: `FILE_ATTRIBUTE_OFFLINE`,
/// `FILE_ATTRIBUTE_RECALL_ON_OPEN`, and `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS`.
/// Any of these bits means reading the file would trigger a network
/// download — Word conversion must never attempt that offline.
///
/// This never opens, reads, or downloads the file — it only inspects
/// metadata already resident in the filesystem's directory entry.
class Win32LocalFileAvailabilityChecker
    implements LocalFileAvailabilityChecker {
  const Win32LocalFileAvailabilityChecker();

  static const int _fileAttributeOffline = 0x00001000;
  static const int _fileAttributeRecallOnOpen = 0x00040000;
  static const int _fileAttributeRecallOnDataAccess = 0x00400000;
  static const int _invalidFileAttributes = 0xFFFFFFFF;
  static const int _cloudPlaceholderMask =
      _fileAttributeOffline |
      _fileAttributeRecallOnOpen |
      _fileAttributeRecallOnDataAccess;

  @override
  bool isLocallyAvailable(String absolutePath) {
    try {
      return using<bool>((arena) {
        final pathPtr = absolutePath.toNativeUtf16(allocator: arena);
        final attributes = GetFileAttributes(pathPtr);
        if (attributes == _invalidFileAttributes) {
          // Could not be read (missing, access denied, etc.). Not this
          // checker's job to report — the caller's own existence/read
          // attempt will surface the real error safely.
          return true;
        }
        return (attributes & _cloudPlaceholderMask) == 0;
      });
    } catch (_) {
      return true;
    }
  }
}
