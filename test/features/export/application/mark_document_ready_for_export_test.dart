// test/features/export/application/mark_document_ready_for_export_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_aggregate.dart';
import 'package:legal_library_manager/features/documents/domain/entities/normalized_draft.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_metadata_repository.dart';
import 'package:legal_library_manager/features/export/application/use_cases/mark_document_ready_for_export.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_eligibility_result.dart';
import 'package:legal_library_manager/features/export/domain/entities/exportable_document_ref.dart';
import 'package:legal_library_manager/features/export/domain/entities/mark_ready_for_export_result.dart';

class _FixedClock extends Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

class _FakeRepo implements DocumentMetadataRepository {
  ExportEligibilityResult eligibilityToReturn = const ExportEligible();
  int markReadyForExportCallCount = 0;
  DateTime? lastMarkReadyForExportNow;

  @override
  Future<ExportEligibilityResult> checkExportEligibility(int documentId) =>
      Future.value(eligibilityToReturn);

  @override
  Future<void> markReadyForExport(int documentId, {required DateTime now}) {
    markReadyForExportCallCount++;
    lastMarkReadyForExportNow = now;
    return Future.value();
  }

  @override
  Future<List<ExportableDocumentRef>> listReadyForExport() =>
      Future.value(const []);

  @override
  Future<DocumentAggregate?> loadAggregate(int documentId) =>
      throw UnimplementedError();

  @override
  Future<void> saveDraft(
    NormalizedDraft draft, {
    required DateTime now,
    required String workflowStatusKey,
    required bool clearClassifiedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> markClassified(int documentId, {required DateTime now}) =>
      throw UnimplementedError();

  @override
  Future<void> returnToInProgress(int documentId, {required DateTime now}) =>
      throw UnimplementedError();
}

void main() {
  late _FakeRepo repo;
  late MarkDocumentReadyForExport useCase;
  final clock = _FixedClock(DateTime.utc(2026, 7, 18, 12));

  setUp(() {
    repo = _FakeRepo();
    useCase = MarkDocumentReadyForExport(repository: repo, clock: clock);
  });

  test('eligible document is transitioned and returns success', () async {
    repo.eligibilityToReturn = const ExportEligible();

    final result = await useCase.call(7);

    expect(result, isA<MarkReadyForExportSuccess>());
    expect(repo.markReadyForExportCallCount, 1);
    expect(repo.lastMarkReadyForExportNow, clock.nowUtc());
  });

  test(
    'ineligible document returns failure with reasons and never transitions',
    () async {
      repo.eligibilityToReturn = const ExportIneligible([
        'Metadata quality must be high or verified.',
      ]);

      final result = await useCase.call(7);

      expect(result, isA<MarkReadyForExportIneligible>());
      expect((result as MarkReadyForExportIneligible).reasons, [
        'Metadata quality must be high or verified.',
      ]);
      expect(repo.markReadyForExportCallCount, 0);
    },
  );
}
