enum CopyRootKind { managedLibrary, databaseBackup, exportRoot }

abstract class CopyRootPicker {
  Future<String?> pick(CopyRootKind kind);
}
