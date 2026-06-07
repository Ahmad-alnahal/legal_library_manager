// Shared fixtures for document metadata tests.
import 'package:drift/drift.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';

/// Deterministic clock for tests.
class FixedClock extends Clock {
  const FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now.toUtc();
}

const String kSeedNow = '2026-01-01T00:00:00.000Z';

/// Inserts a bare document row (as import would) and returns its id.
Future<int> insertDocument(AppDatabase db) => db
    .into(db.documents)
    .insert(
      DocumentsCompanion.insert(createdAt: kSeedNow, updatedAt: kSeedNow),
    );

int _pathCounter = 0;

/// Adds a physical file to [docId] with the given role/health, returns file id.
Future<int> addFile(
  AppDatabase db,
  int docId, {
  required String role,
  required String health,
}) {
  _pathCounter++;
  return db
      .into(db.documentFiles)
      .insert(
        DocumentFilesCompanion.insert(
          documentId: docId,
          fileRoleKey: role,
          fileName: 'file_$_pathCounter.pdf',
          absolutePath:
              r'C:\sample\file_'
              '$_pathCounter.pdf',
          extension: '.pdf',
          fileSizeBytes: 1024,
          createdAt: kSeedNow,
          updatedAt: kSeedNow,
          fileHealthKey: Value(health),
        ),
      );
}

Future<int> addHealthySource(AppDatabase db, int docId) =>
    addFile(db, docId, role: 'source_original', health: 'healthy');

/// Inserts a conversion record for a converted_pdf output file.
Future<void> addConversion(
  AppDatabase db,
  int docId,
  int outputFileId, {
  required String statusKey,
  bool? qualityApproved,
}) => db
    .into(db.fileConversions)
    .insert(
      FileConversionsCompanion.insert(
        documentId: docId,
        sourceFileId: outputFileId,
        statusKey: statusKey,
        createdAt: kSeedNow,
        updatedAt: kSeedNow,
        outputFileId: Value(outputFileId),
        qualityApproved: Value(qualityApproved),
      ),
    );

Future<int> typeId(AppDatabase db, String key) async => (await (db.select(
  db.documentTypes,
)..where((t) => t.key.equals(key))).getSingle()).id;

Future<int> mainId(AppDatabase db, String key) async => (await (db.select(
  db.mainCategories,
)..where((m) => m.key.equals(key))).getSingle()).id;

Future<int> subId(AppDatabase db, String key) async => (await (db.select(
  db.subCategories,
)..where((s) => s.key.equals(key))).getSingle()).id;
