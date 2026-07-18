// test/features/managed_copy/data/export_root_setting_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/managed_copy/data/repositories/drift_managed_copy_repository.dart';

class _FakeClock extends Clock {
  const _FakeClock();
  @override
  DateTime nowUtc() => DateTime.utc(2026, 7, 18, 12, 0, 0);
}

void main() {
  late AppDatabase db;
  late DriftManagedCopyRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = DriftManagedCopyRepository(db, const _FakeClock());
  });

  tearDown(() => db.close());

  test('loadExportRoot returns null when key absent', () async {
    expect(await repo.loadExportRoot(), isNull);
  });

  test('saveExportRoot persists; loadExportRoot returns it', () async {
    await repo.saveExportRoot(r'D:\Export');
    expect(await repo.loadExportRoot(), r'D:\Export');
  });

  test('saveExportRoot overwrites a previously saved value', () async {
    await repo.saveExportRoot(r'D:\Export');
    await repo.saveExportRoot(r'D:\Export2');
    expect(await repo.loadExportRoot(), r'D:\Export2');
  });
}
