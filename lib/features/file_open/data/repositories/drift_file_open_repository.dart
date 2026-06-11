// lib/features/file_open/data/repositories/drift_file_open_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/time/clock.dart';
import '../../domain/entities/file_open_record.dart';
import '../../domain/entities/open_target.dart';
import '../../domain/repositories/file_open_repository.dart';

/// Drift-backed [FileOpenRepository].
///
/// Reads from [document_files]; appends to [file_open_events].
/// Never modifies [documents], [document_files], workflow statuses, or source
/// files.
class DriftFileOpenRepository implements FileOpenRepository {
  const DriftFileOpenRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<FileOpenRecord?> loadFileRecord(int fileId) async {
    final rows = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.id.equals(fileId))).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return FileOpenRecord(
      fileId: row.id,
      documentId: row.documentId,
      absolutePath: row.absolutePath,
      extension: row.extension,
      fileHealthKey: row.fileHealthKey,
    );
  }

  @override
  Future<void> recordOpenEvent({
    required int fileId,
    required int? documentId,
    required OpenTarget target,
    required String resultKey,
    String? errorCode,
    String? messageSafe,
  }) async {
    await _db
        .into(_db.fileOpenEvents)
        .insert(
          FileOpenEventsCompanion.insert(
            documentId: Value(documentId),
            fileId: fileId,
            openTargetKey: target.name,
            resultKey: resultKey,
            errorCode: Value(errorCode),
            messageSafe: Value(messageSafe),
            createdAt: _clock.nowUtc().toIso8601String(),
          ),
        );
  }
}
