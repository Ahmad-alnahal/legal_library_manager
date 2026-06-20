// test/features/managed_copy/data/sqlite_database_backup_service_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/features/managed_copy/data/services/sqlite_database_backup_service.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/database_backup_service.dart';

/// SQLite magic header: "SQLite format 3\0" (16 bytes).
const List<int> _kMagic = [
  83,
  81,
  76,
  105,
  116,
  101,
  32,
  102,
  111,
  114,
  109,
  97,
  116,
  32,
  51,
  0,
];

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_svc_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('SqliteDatabaseBackupService.verifyBackupFile', () {
    test('returns false for a file shorter than 100 bytes', () async {
      final f = File('${tempDir.path}\\short.sqlite');
      // Write valid magic but only 50 bytes total — header check requires >= 100.
      final bytes = Uint8List(50);
      for (int i = 0; i < _kMagic.length; i++) {
        bytes[i] = _kMagic[i];
      }
      await f.writeAsBytes(bytes);
      expect(SqliteDatabaseBackupService.verifyBackupFile(f.path), isFalse);
    });

    test(
      'returns false for a file with valid header but corrupt body',
      () async {
        final f = File('${tempDir.path}\\corrupt.sqlite');
        // Write valid 16-byte magic followed by garbage up to 200 bytes.
        final bytes = Uint8List(200);
        for (int i = 0; i < _kMagic.length; i++) {
          bytes[i] = _kMagic[i];
        }
        // Fill remainder with non-zero garbage — sqlite3 will fail to open it.
        for (int i = _kMagic.length; i < bytes.length; i++) {
          bytes[i] = 0xFF;
        }
        await f.writeAsBytes(bytes);
        expect(SqliteDatabaseBackupService.verifyBackupFile(f.path), isFalse);
      },
    );

    test('returns false for a non-existent file', () {
      expect(
        SqliteDatabaseBackupService.verifyBackupFile(
          r'C:\does_not_exist_abc123.sqlite',
        ),
        isFalse,
      );
    });

    test('returns false for an empty file', () async {
      final f = File('${tempDir.path}\\empty.sqlite');
      await f.writeAsBytes(<int>[]);
      expect(SqliteDatabaseBackupService.verifyBackupFile(f.path), isFalse);
    });
  });

  group('SqliteDatabaseBackupService.createBackup — path guards', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('rejects a backup root containing a single quote', () async {
      final service = SqliteDatabaseBackupService(db);
      final result = await service.createBackup(
        backupRoot: r"C:\Ahmad's Files",
        operationId: 'op-1',
        timestamp: DateTime.utc(2026, 6, 18),
      );
      expect(result, isA<BackupFailure>());
      // The DB must never have been touched — no backup file anywhere in tempDir.
      expect(tempDir.listSync(), isEmpty);
    });

    test('rejects a backup root containing a null byte', () async {
      final service = SqliteDatabaseBackupService(db);
      final result = await service.createBackup(
        backupRoot: 'C:\\evil\x00path',
        operationId: 'op-2',
        timestamp: DateTime.utc(2026, 6, 18),
      );
      expect(result, isA<BackupFailure>());
      expect(tempDir.listSync(), isEmpty);
    });

    test('rejects a backup root containing both a quote and a null byte',
        () async {
      final service = SqliteDatabaseBackupService(db);
      final result = await service.createBackup(
        backupRoot: "C:\\bad'\x00root",
        operationId: 'op-3',
        timestamp: DateTime.utc(2026, 6, 18),
      );
      expect(result, isA<BackupFailure>());
      expect(tempDir.listSync(), isEmpty);
    });
  });
}
