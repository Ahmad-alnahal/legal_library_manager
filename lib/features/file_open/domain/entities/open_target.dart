// lib/features/file_open/domain/entities/open_target.dart

/// Whether the safe-open operation targets the file itself or its parent folder.
enum OpenTarget {
  /// Open the registered PDF in the Windows default associated application.
  file,

  /// Open the folder containing the registered file, selecting it when the OS
  /// supports it.
  folder,
}
