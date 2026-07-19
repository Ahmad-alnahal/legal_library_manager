// test/features/managed_copy/presentation/bloc/copy_settings_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/apply_default_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/configure_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/repair_copy_root.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/copy_root_picker.dart';
import 'package:legal_library_manager/features/managed_copy/presentation/bloc/copy_settings_bloc.dart';

// ── Test doubles for the four unused application dependencies ──────────────

class _NeverInitializeCopyRoots implements InitializeCopyRoots {
  @override
  Future<CopyRootsSetupReport> call() async =>
      throw UnimplementedError('not used by export-root tests');
}

class _NeverConfigureCopyRoots implements ConfigureCopyRoots {
  @override
  Future<ConfigureCopyRootsResult> call(String? managed, String? backup) =>
      throw UnimplementedError('not used by export-root tests');
}

class _NeverRepairCopyRoot implements RepairCopyRoot {
  @override
  Future<RepairCopyRootResult> call(CopyRootKind kind) =>
      throw UnimplementedError('not used by export-root tests');
}

class _NeverApplyDefaultCopyRoots implements ApplyDefaultCopyRoots {
  @override
  Future<ApplyDefaultCopyRootsResult> call() async =>
      throw UnimplementedError('not used by export-root tests');
}

class _FakePicker implements CopyRootPicker {
  _FakePicker(this.result);
  String? result;
  final List<CopyRootKind> calls = [];

  @override
  Future<String?> pick(CopyRootKind kind) async {
    calls.add(kind);
    return result;
  }
}

/// Minimal in-memory [ManagedCopyRepository] fake: only the export-root and
/// startup-recovery methods the bloc actually calls are implemented.
class _FakeManagedCopyRepository implements ManagedCopyRepository {
  String? exportRoot;
  final List<String> savedExportRoots = [];

  @override
  Future<String?> loadExportRoot() async => exportRoot;

  @override
  Future<void> saveExportRoot(String path) async {
    savedExportRoots.add(path);
    exportRoot = path.trim().isEmpty ? null : path;
  }

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by export-root tests');
}

void main() {
  late _FakePicker picker;
  late _FakeManagedCopyRepository repository;
  late CopySettingsBloc bloc;

  setUp(() {
    picker = _FakePicker(r'D:\Exports');
    repository = _FakeManagedCopyRepository();
    bloc = CopySettingsBloc(
      picker,
      _NeverConfigureCopyRoots(),
      _NeverInitializeCopyRoots(),
      _NeverRepairCopyRoot(),
      _NeverApplyDefaultCopyRoots(),
      repository,
    );
  });

  tearDown(() => bloc.close());

  group('ExportRootSelectionRequested', () {
    test('persists the picked path and updates state', () async {
      final states = <CopySettingsState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ExportRootSelectionRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(picker.calls, [CopyRootKind.exportRoot]);
      expect(repository.savedExportRoots, [r'D:\Exports']);
      expect(states.last.exportRoot, r'D:\Exports');
      expect(states.last.busy, isFalse);
    });

    test('cancelling the picker leaves exportRoot unchanged', () async {
      picker.result = null;
      final states = <CopySettingsState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ExportRootSelectionRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(repository.savedExportRoots, isEmpty);
      expect(states.last.exportRoot, isNull);
      expect(states.last.busy, isFalse);
    });
  });

  group('ExportRootClearedToDefault', () {
    test('clears the path and sets exportRoot null in state', () async {
      repository.exportRoot = r'D:\Exports';
      bloc = CopySettingsBloc(
        picker,
        _NeverConfigureCopyRoots(),
        _NeverInitializeCopyRoots(),
        _NeverRepairCopyRoot(),
        _NeverApplyDefaultCopyRoots(),
        repository,
      );

      final states = <CopySettingsState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ExportRootClearedToDefault());
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(repository.savedExportRoots, ['']);
      expect(states.last.exportRoot, isNull);
    });
  });
}
