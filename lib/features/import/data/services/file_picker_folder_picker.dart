// lib/features/import/data/services/file_picker_folder_picker.dart

import 'package:file_picker/file_picker.dart';

import '../../application/folder_picker.dart';

/// [FolderPicker] backed by `file_picker`'s native directory dialog. Returns the
/// selected absolute path or null on cancel. It only opens a chooser — it never
/// reads, scans, or imports.
class FilePickerFolderPicker implements FolderPicker {
  const FilePickerFolderPicker();

  @override
  Future<String?> pickDirectory() {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختيار مجلد المصدر',
      lockParentWindow: true,
    );
  }
}
