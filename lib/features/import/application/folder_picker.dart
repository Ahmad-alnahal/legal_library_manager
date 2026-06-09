// lib/features/import/application/folder_picker.dart

/// Opens a native folder-selection dialog and returns the chosen absolute path,
/// or null when the user cancels. Selecting a folder never scans or imports.
/// Implementations live in the data layer.
abstract class FolderPicker {
  Future<String?> pickDirectory();
}
