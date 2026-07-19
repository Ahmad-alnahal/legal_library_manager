// test/features/export/presentation/bloc/mark_ready_for_export_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/export/domain/entities/mark_ready_for_export_result.dart';
import 'package:legal_library_manager/features/export/presentation/bloc/mark_ready_for_export_bloc.dart';

void main() {
  group('MarkReadyForExportBloc', () {
    test('initial state is idle', () {
      final bloc = MarkReadyForExportBloc.executor(
        (_) async => const MarkReadyForExportSuccess(),
      );
      expect(bloc.state.status, MarkReadyForExportStatus.idle);
      expect(bloc.state.sequence, 0);
      bloc.close();
    });

    test(
      'success path emits running then success and increments sequence',
      () async {
        final bloc = MarkReadyForExportBloc.executor(
          (_) async => const MarkReadyForExportSuccess(),
        );

        final states = <MarkReadyForExportState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const MarkReadyForExportRequested(1));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(states.first.status, MarkReadyForExportStatus.running);
        expect(states.last.status, MarkReadyForExportStatus.success);
        expect(states.last.documentId, 1);
        expect(states.last.sequence, 1);
        bloc.close();
      },
    );

    test(
      'ineligible path emits running then ineligible with reasons',
      () async {
        final bloc = MarkReadyForExportBloc.executor(
          (_) async => const MarkReadyForExportIneligible(['file_not_healthy']),
        );

        final states = <MarkReadyForExportState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const MarkReadyForExportRequested(2));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(states.first.status, MarkReadyForExportStatus.running);
        expect(states.last.status, MarkReadyForExportStatus.ineligible);
        expect(states.last.ineligibleReasons, ['file_not_healthy']);
        expect(states.last.sequence, 1);
        bloc.close();
      },
    );

    test('unexpected exception emits failed and increments sequence', () async {
      final bloc = MarkReadyForExportBloc.executor(
        (_) async => throw StateError('boom'),
      );

      final states = <MarkReadyForExportState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const MarkReadyForExportRequested(3));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states.last.status, MarkReadyForExportStatus.failed);
      expect(states.last.sequence, 1);
      bloc.close();
    });

    test('overlapping guard ignores a second event while running', () async {
      var callCount = 0;
      final bloc = MarkReadyForExportBloc.executor((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const MarkReadyForExportSuccess();
      });

      bloc.add(const MarkReadyForExportRequested(1));
      bloc.add(const MarkReadyForExportRequested(1));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(callCount, 1);
      bloc.close();
    });
  });
}
