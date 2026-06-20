enum CopyRootKind { managedLibrary, databaseBackup }

abstract class CopyRootPicker {
  Future<String?> pick(CopyRootKind kind);
}
