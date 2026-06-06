import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Name of the on-disk SQLite database file.
const String kDatabaseFileName = 'legal_library.sqlite';

/// Opens the production database file inside the OS application-support
/// directory.
///
/// The file lives in app-managed storage only — never inside user source
/// folders — consistent with the source-file safety rules. Opening is lazy so
/// the (async) directory lookup happens off the constructor path.
LazyDatabase openProductionConnection() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationSupportDirectory();
    final String dbPath = p.join(dir.path, kDatabaseFileName);
    return NativeDatabase.createInBackground(File(dbPath));
  });
}
