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

    test(
      'rejects a backup root containing both a quote and a null byte',
      () async {
        final service = SqliteDatabaseBackupService(db);
        final result = await service.createBackup(
          backupRoot: "C:\\bad'\x00root",
          operationId: 'op-3',
          timestamp: DateTime.utc(2026, 6, 18),
        );
        expect(result, isA<BackupFailure>());
        expect(tempDir.listSync(), isEmpty);
      },
    );
  });

  group('SqliteDatabaseBackupService.createBackup — rolling pruning', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    File makeOldBackup(String dateStr, String opId) {
      final name = 'legal_library_backup_${dateStr}_$opId.sqlite';
      final f = File('${tempDir.path}\\$name');
      f.writeAsBytesSync(Uint8List(200));
      return f;
    }

    List<String> ownedBackupNames() => tempDir
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split(r'\').last)
        .where(
          (name) =>
              name.startsWith('legal_library_backup_') &&
              name.endsWith('.sqlite'),
        )
        .toList();

    test('no pruning when total stays at 3 or fewer', () async {
      makeOldBackup('2020-01-01_000000', 'op-a');
      makeOldBackup('2020-01-02_000000', 'op-b');

      final service = SqliteDatabaseBackupService(db);
      final result = await service.createBackup(
        backupRoot: tempDir.path,
        operationId: 'op-new',
        timestamp: DateTime.utc(2026, 1, 1),
      );

      expect(result, isA<BackupSuccess>());
      expect(ownedBackupNames(), hasLength(3));
    });

    test('oldest file pruned when 4th backup is created', () async {
      makeOldBackup('2020-01-01_000000', 'op-a');
      makeOldBackup('2020-01-02_000000', 'op-b');
      makeOldBackup('2020-01-03_000000', 'op-c');

      final service = SqliteDatabaseBackupService(db);
      final result = await service.createBackup(
        backupRoot: tempDir.path,
        operationId: 'op-new',
        timestamp: DateTime.utc(2026, 1, 1),
      );

      expect(result, isA<BackupSuccess>());
      final names = ownedBackupNames();
      expect(names, hasLength(3));
      expect(
        names.any((n) => n.contains('2020-01-01')),
        isFalse,
        reason: 'oldest backup should have been pruned',
      );
      expect(names.any((n) => n.contains('2020-01-02')), isTrue);
      expect(names.any((n) => n.contains('2020-01-03')), isTrue);
      expect(names.any((n) => n.contains('2026-01-01')), isTrue);
    });

    test('multiple old files pruned (more than 1 over the limit)', () async {
      makeOldBackup('2019-01-01_000000', 'op-a');
      makeOldBackup('2020-01-01_000000', 'op-b');
      makeOldBackup('2021-01-01_000000', 'op-c');
      makeOldBackup('2022-01-01_000000', 'op-d');
      makeOldBackup('2023-01-01_000000', 'op-e');

      final service = SqliteDatabaseBackupService(db);
      final result = await service.createBackup(
        backupRoot: tempDir.path,
        operationId: 'op-new',
        timestamp: DateTime.utc(2026, 1, 1),
      );

      expect(result, isA<BackupSuccess>());
      final names = ownedBackupNames();
      expect(names, hasLength(3));
      expect(names.any((n) => n.contains('2019-01-01')), isFalse);
      expect(names.any((n) => n.contains('2020-01-01')), isFalse);
      expect(names.any((n) => n.contains('2021-01-01')), isFalse);
      expect(names.any((n) => n.contains('2022-01-01')), isTrue);
      expect(names.any((n) => n.contains('2023-01-01')), isTrue);
      expect(names.any((n) => n.contains('2026-01-01')), isTrue);
    });

    test('non-owned files in the same folder are never touched', () async {
      makeOldBackup('2020-01-01_000000', 'op-a');
      makeOldBackup('2020-01-02_000000', 'op-b');
      makeOldBackup('2020-01-03_000000', 'op-c');
      final readme = File('${tempDir.path}\\readme.txt');
      readme.writeAsStringSync('not a backup');

      final service = SqliteDatabaseBackupService(db);
      final result = await service.createBackup(
        backupRoot: tempDir.path,
        operationId: 'op-new',
        timestamp: DateTime.utc(2026, 1, 1),
      );

      expect(result, isA<BackupSuccess>());
      expect(readme.existsSync(), isTrue);
      expect(ownedBackupNames(), hasLength(3));
    });
  });
}
