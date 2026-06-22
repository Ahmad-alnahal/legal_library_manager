// test/features/managed_copy/presentation/bloc/copy_integrity_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/reconcile_integrity_result.dart';
import 'package:legal_library_manager/features/managed_copy/presentation/bloc/copy_integrity_bloc.dart';

// ── Test double ───────────────────────────────────────────────────────────────

class _FakeReconcile {
  final ReconcileIntegrityResult result;
  final bool throws;

  const _FakeReconcile({
    this.result = ReconcileIntegrityResult.empty,
    this.throws = false,
  });

  Future<ReconcileIntegrityResult> call() async {
    if (throws) throw StateError('reconcile failed');
    return result;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('CopyIntegrityBloc', () {
    test('initial state is idle with no messageKey', () {
      final bloc = CopyIntegrityBloc(_FakeReconcile().call);
      expect(bloc.state.busy, isFalse);
      expect(bloc.state.messageKey, isNull);
      expect(bloc.state.sequence, 0);
      bloc.close();
    });

    test('emits busy then clean result when all files are healthy', () async {
      const result = ReconcileIntegrityResult(
        healthyCount: 3,
        missingCount: 0,
        corruptedCount: 0,
        restoredCount: 0,
        downgradedDocumentCount: 0,
        failedCount: 0,
      );
      final bloc = CopyIntegrityBloc(_FakeReconcile(result: result).call);

      final states = <CopyIntegrityState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const CopyIntegrityCheckRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.first.busy, isTrue);
      expect(states.last.busy, isFalse);
      expect(states.last.messageKey, 'clean');
      expect(states.last.issueCount, 0);
      bloc.close();
    });

    test('emits busy then issues result when missing files found', () async {
      const result = ReconcileIntegrityResult(
        healthyCount: 1,
        missingCount: 2,
        corruptedCount: 1,
        restoredCount: 0,
        downgradedDocumentCount: 1,
        failedCount: 0,
      );
      final bloc = CopyIntegrityBloc(_FakeReconcile(result: result).call);

      final states = <CopyIntegrityState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const CopyIntegrityCheckRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.last.messageKey, 'issues');
      expect(states.last.issueCount, 3); // 2 missing + 1 corrupted
      bloc.close();
    });

    test('emits failed state when use case throws', () async {
      final bloc = CopyIntegrityBloc(_FakeReconcile(throws: true).call);

      final states = <CopyIntegrityState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const CopyIntegrityCheckRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.last.messageKey, 'failed');
      expect(states.last.busy, isFalse);
      bloc.close();
    });

    test('increments sequence on each result', () async {
      final bloc = CopyIntegrityBloc(_FakeReconcile().call);

      final states = <CopyIntegrityState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const CopyIntegrityCheckRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.last.sequence, 1);
      bloc.close();
    });

    test('second event is dropped while first is in flight', () async {
      var callCount = 0;
      Future<ReconcileIntegrityResult> slowReconcile() async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return ReconcileIntegrityResult.empty;
      }

      final bloc = CopyIntegrityBloc(slowReconcile);

      // Add two events quickly
      bloc.add(const CopyIntegrityCheckRequested());
      bloc.add(const CopyIntegrityCheckRequested());

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(callCount, 1); // droppable — only first runs
      bloc.close();
    });

    test('action shows loading (busy=true) while running', () async {
      final bloc = CopyIntegrityBloc(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return ReconcileIntegrityResult.empty;
      });

      final states = <CopyIntegrityState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const CopyIntegrityCheckRequested());
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.first.busy, isTrue);
      bloc.close();
    });

    test('no raw file paths are emitted in any state field', () async {
      const result = ReconcileIntegrityResult(
        healthyCount: 1,
        missingCount: 1,
        corruptedCount: 0,
        restoredCount: 0,
        downgradedDocumentCount: 1,
        failedCount: 0,
      );
      final bloc = CopyIntegrityBloc(_FakeReconcile(result: result).call);

      final states = <CopyIntegrityState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const CopyIntegrityCheckRequested());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      for (final s in states) {
        // messageKey is a short code like 'clean'|'issues'|'failed' — never a path
        final key = s.messageKey ?? '';
        expect(
          key.contains(r'\'),
          isFalse,
          reason: 'messageKey must not be a path',
        );
        expect(
          key.contains('/'),
          isFalse,
          reason: 'messageKey must not be a path',
        );
      }
      bloc.close();
    });
  });
}
