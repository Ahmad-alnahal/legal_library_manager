import 'package:file_picker/file_picker.dart';

import '../../domain/services/copy_root_picker.dart';

class FilePickerCopyRootPicker implements CopyRootPicker {
  const FilePickerCopyRootPicker();

  @override
  Future<String?> pick(CopyRootKind kind) {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: switch (kind) {
        CopyRootKind.managedLibrary => 'اختيار مجلد المكتبة المدارة',
        CopyRootKind.databaseBackup => 'اختيار مجلد النسخ الاحتياطي',
      },
      lockParentWindow: true,
    );
  }
}
