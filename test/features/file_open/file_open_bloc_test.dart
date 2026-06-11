// test/features/file_open/file_open_bloc_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/file_open/application/open_file_use_case.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_file_result.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_target.dart';
import 'package:legal_library_manager/features/file_open/domain/repositories/file_open_repository.dart';
import 'package:legal_library_manager/features/file_open/domain/services/file_existence_checker.dart';
import 'package:legal_library_manager/features/file_open/domain/services/os_file_opener.dart';
import 'package:legal_library_manager/features/file_open/presentation/bloc/file_open_bloc.dart';
import 'package:legal_library_manager/features/file_open/presentation/bloc/file_open_event.dart';
import 'package:legal_library_manager/features/file_open/presentation/bloc/file_open_state.dart';

// ---------------------------------------------------------------------------
// Test doubles. The use case's execute() is overridden, so the constructor
// dependencies are never exercised.
// ---------------------------------------------------------------------------

/// Controllable time source injected in cooldown tests.
class _FakeClock {
  DateTime _current = DateTime(2026, 1, 1);
  DateTime call() => _current;
  void advance(Duration by) => _current = _current.add(by);
}

class _DummyRepo implements FileOpenRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used');
}

class _DummyChecker implements FileExistenceChecker {
  @override
  FileExistenceStatus checkFile(String absolutePath) =>
      throw UnimplementedError('not used');
}

class _DummyOpener implements OsFileOpener {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used');
}

class _FakeUseCase extends OpenFileUseCase {
  _FakeUseCase()
    : super(
        repository: _DummyRepo(),
        existenceChecker: _DummyChecker(),
        osOpener: _DummyOpener(),
      );

  final List<({int fileId, OpenTarget target})> calls = [];

  /// When set, execute() awaits this gate, simulating a slow OS open.
  Completer<OpenFileResult>? gate;

  /// Returned when [gate] is null.
  OpenFileResult result = const OpenFileSuccess(target: OpenTarget.file);

  @override
  Future<OpenFileResult> execute(int fileId, OpenTarget target) async {
    calls.add((fileId: fileId, target: target));
    final pending = gate;
    if (pending != null) return pending.future;
    return result;
  }
}

void main() {
  late _FakeUseCase useCase;
  late FileOpenBloc bloc;

  setUp(() {
    useCase = _FakeUseCase();
    bloc = FileOpenBloc(useCase);
  });

  tearDown(() => bloc.close());

  test(
    'dispatches the registered file ID and target to the use case',
    () async {
      bloc.add(const FileOpenRequested(7, OpenTarget.folder));
      await bloc.stream.firstWhere((s) => s.isTerminal);

      expect(useCase.calls, [(fileId: 7, target: OpenTarget.folder)]);
    },
  );

  test('emits opening then success for a successful file open', () async {
    useCase.result = const OpenFileSuccess(target: OpenTarget.file);

    final expectation = expectLater(
      bloc.stream,
      emitsInOrder(const [
        FileOpenUiState(
          status: FileOpenStatus.opening,
          activeFileId: 1,
          activeTarget: OpenTarget.file,
        ),
        FileOpenUiState(
          status: FileOpenStatus.success,
          activeFileId: 1,
          activeTarget: OpenTarget.file,
        ),
      ]),
    );

    bloc.add(const FileOpenRequested(1, OpenTarget.file));
    await expectation;
  });

  test('maps a blocked result to a blocked state with stable code', () async {
    useCase.result = const OpenFileBlocked(
      code: FileOpenError.unsupportedExtension,
      safeMessage: 'unused',
    );

    bloc.add(const FileOpenRequested(2, OpenTarget.file));
    final state = await bloc.stream.firstWhere((s) => s.isTerminal);

    expect(state.status, FileOpenStatus.blocked);
    expect(state.errorCode, FileOpenError.unsupportedExtension);
  });

  test('maps a failed result to a failed state with stable code', () async {
    useCase.result = const OpenFileFailed(
      code: FileOpenError.noAssociatedApplication,
      safeMessage: 'unused',
    );

    bloc.add(const FileOpenRequested(3, OpenTarget.file));
    final state = await bloc.stream.firstWhere((s) => s.isTerminal);

    expect(state.status, FileOpenStatus.failed);
    expect(state.errorCode, FileOpenError.noAssociatedApplication);
  });

  test('maps an audit failure to an auditFailure state', () async {
    useCase.result = const OpenFileAuditFailure(target: OpenTarget.folder);

    bloc.add(const FileOpenRequested(4, OpenTarget.folder));
    final state = await bloc.stream.firstWhere((s) => s.isTerminal);

    expect(state.status, FileOpenStatus.auditFailure);
    expect(state.activeTarget, OpenTarget.folder);
    expect(state.errorCode, isNull);
  });

  test('prevents overlapping requests while one open is in flight', () async {
    final gate = Completer<OpenFileResult>();
    useCase.gate = gate;

    // First request enters the in-flight state and awaits the gate.
    bloc.add(const FileOpenRequested(1, OpenTarget.file));
    await bloc.stream.firstWhere((s) => s.status == FileOpenStatus.opening);

    // Second request while busy must be dropped.
    bloc.add(const FileOpenRequested(2, OpenTarget.folder));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(useCase.calls, [(fileId: 1, target: OpenTarget.file)]);

    gate.complete(const OpenFileSuccess(target: OpenTarget.file));
    await bloc.stream.firstWhere((s) => s.isTerminal);

    // A new request after completion is accepted.
    bloc.add(const FileOpenRequested(2, OpenTarget.folder));
    await bloc.stream.firstWhere((s) => s.isTerminal);
    expect(useCase.calls, [
      (fileId: 1, target: OpenTarget.file),
      (fileId: 2, target: OpenTarget.folder),
    ]);
  });

  test('only the active file/target reports loading', () async {
    final gate = Completer<OpenFileResult>();
    useCase.gate = gate;

    bloc.add(const FileOpenRequested(5, OpenTarget.file));
    final opening = await bloc.stream.firstWhere(
      (s) => s.status == FileOpenStatus.opening,
    );

    expect(opening.isActive(5, OpenTarget.file), isTrue);
    expect(opening.isActive(5, OpenTarget.folder), isFalse);
    expect(opening.isActive(6, OpenTarget.file), isFalse);

    gate.complete(const OpenFileSuccess(target: OpenTarget.file));
    await bloc.stream.firstWhere((s) => s.isTerminal);
  });

  test('feedback handled returns the controller to idle', () async {
    useCase.result = const OpenFileSuccess(target: OpenTarget.file);
    bloc.add(const FileOpenRequested(1, OpenTarget.file));
    await bloc.stream.firstWhere((s) => s.status == FileOpenStatus.success);

    bloc.add(const FileOpenFeedbackHandled());
    final idle = await bloc.stream.firstWhere(
      (s) => s.status == FileOpenStatus.idle,
    );
    expect(idle, const FileOpenUiState());
  });

  test('state never carries raw exception text or paths', () async {
    useCase.result = const OpenFileFailed(
      code: FileOpenError.osLaunchFailed,
      safeMessage: 'unused',
    );
    bloc.add(const FileOpenRequested(1, OpenTarget.file));
    final state = await bloc.stream.firstWhere((s) => s.isTerminal);

    final dump = state.props.join('|') + state.toString();
    expect(dump.contains('Exception'), isFalse);
    expect(dump.contains('StackTrace'), isFalse);
    expect(dump.contains(r'C:\'), isFalse);
    expect(dump.contains('/'), isFalse);
  });

  // ---------------------------------------------------------------------------
  // Cooldown guard — rapid identical requests for the same fileId + target
  // invoke the OS opener only once within the 1-second window.
  // ---------------------------------------------------------------------------

  group('FileOpenBloc — cooldown guard', () {
    late _FakeClock clock;
    late _FakeUseCase cooldownUseCase;
    late FileOpenBloc cooldownBloc;

    setUp(() {
      clock = _FakeClock();
      cooldownUseCase = _FakeUseCase();
      cooldownBloc = FileOpenBloc(cooldownUseCase, clock: clock.call);
    });

    tearDown(() => cooldownBloc.close());

    test(
      'rapid identical Open Folder events invoke the use case only once',
      () async {
        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
        await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

        // Second identical request arrives within the cooldown window.
        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cooldownUseCase.calls, hasLength(1));
        expect(cooldownUseCase.calls.single.target, OpenTarget.folder);
      },
    );

    test(
      'rapid identical Open File events invoke the use case only once',
      () async {
        cooldownUseCase.result = const OpenFileSuccess(target: OpenTarget.file);
        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.file));
        await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

        // Second identical request arrives within the cooldown window.
        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.file));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cooldownUseCase.calls, hasLength(1));
        expect(cooldownUseCase.calls.single.target, OpenTarget.file);
      },
    );

    test(
      'request for the same key is accepted again after the cooldown',
      () async {
        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
        await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

        // Advance clock past the 1-second cooldown.
        clock.advance(const Duration(seconds: 1));

        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
        await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

        expect(cooldownUseCase.calls, hasLength(2));
      },
    );

    test(
      'different file IDs have independent cooldowns and do not block each other',
      () async {
        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
        await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

        // File ID 2 has its own cooldown slot — not blocked by ID 1.
        cooldownBloc.add(const FileOpenRequested(2, OpenTarget.folder));
        await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

        expect(cooldownUseCase.calls, [
          (fileId: 1, target: OpenTarget.folder),
          (fileId: 2, target: OpenTarget.folder),
        ]);
      },
    );

    test('Open File and Open Folder for the same file use independent cooldown '
        'keys and do not block each other', () async {
      cooldownUseCase.result = const OpenFileSuccess(target: OpenTarget.file);
      cooldownBloc.add(const FileOpenRequested(1, OpenTarget.file));
      await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

      // Open Folder for the same file ID has its own cooldown slot.
      cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
      await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

      expect(cooldownUseCase.calls, [
        (fileId: 1, target: OpenTarget.file),
        (fileId: 1, target: OpenTarget.folder),
      ]);
    });

    test(
      'ignored duplicate events create no additional use case calls',
      () async {
        cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
        await cooldownBloc.stream.firstWhere((s) => s.isTerminal);

        // Fire 5 rapid duplicates within the cooldown window.
        for (var i = 0; i < 5; i++) {
          cooldownBloc.add(const FileOpenRequested(1, OpenTarget.folder));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Only the original accepted request reached the use case.
        expect(cooldownUseCase.calls, hasLength(1));
      },
    );
  });
}
