// test/features/import/widgets/import_history_section_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_record.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/usecases/get_recent_import_batches_use_case.dart';
import 'package:legal_library_manager/features/import/presentation/bloc/import_history_bloc.dart';
import 'package:legal_library_manager/features/import/presentation/widgets/import_history_section.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

import '../support/import_fakes.dart';

// Stable Arabic strings mirroring lib/l10n/app_ar.arb.
const String _historyTitle = 'سجل الاستيراد';
const String _emptyMsg = 'لا توجد عمليات استيراد سابقة.';
const String _completedChip = 'مكتمل';
const String _failedChip = 'فشل';
const String _cancelledChip = 'ملغى';
const String _interruptedChip = 'انقطع';
const String _interruptedNote =
    'توقف الاستيراد بسبب إغلاق التطبيق. الاستئناف التلقائي غير مدعوم حالياً.';
const String _reuseFolderBtn = 'استيراد جديد من نفس المجلد';

ImportBatchRecord _batch({
  ImportBatchStatus status = ImportBatchStatus.completed,
  String folder = r'C:\src',
  int imported = 5,
  int failed = 1,
  int discovered = 6,
}) => ImportBatchRecord(
  id: 1,
  batchCode: 'IMPORT-0000001',
  sourceFolder: folder,
  status: status,
  discoveredCount: discovered,
  importedCount: imported,
  duplicateCount: 0,
  failedCount: failed,
  pairedCount: 0,
  startedAt: DateTime.utc(2026, 6, 28, 10),
  completedAt: DateTime.utc(2026, 6, 28, 11),
);

ImportHistoryBloc _buildBloc(List<ImportBatchRecord> batches) {
  return ImportHistoryBloc(
    getRecentBatches: GetRecentImportBatchesUseCase(
      FakeImportRepository(recentBatches: batches),
    ),
    jobSnapshots: const Stream.empty(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  ImportHistoryBloc bloc, {
  void Function(String)? onReuseFolder,
  bool isImportActive = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: BlocProvider<ImportHistoryBloc>.value(
          value: bloc,
          child: ImportHistorySection(
            isImportActive: isImportActive,
            onReuseFolder: onReuseFolder ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows title always', (tester) async {
    final bloc = _buildBloc([]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_historyTitle), findsOneWidget);
  });

  testWidgets('shows empty message when no batches', (tester) async {
    final bloc = _buildBloc([]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_emptyMsg), findsOneWidget);
  });

  testWidgets('shows completed status chip for completed batch', (
    tester,
  ) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.completed)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_completedChip), findsOneWidget);
  });

  testWidgets('shows failed status chip for failed batch', (tester) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.failed)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_failedChip), findsOneWidget);
  });

  testWidgets('shows cancelled status chip for cancelled batch', (
    tester,
  ) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.cancelled)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_cancelledChip), findsOneWidget);
  });

  testWidgets('shows interrupted chip and note for interrupted batch', (
    tester,
  ) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.interrupted)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_interruptedChip), findsOneWidget);
    expect(find.text(_interruptedNote), findsOneWidget);
  });

  testWidgets('shows reuse-folder button for interrupted batch', (
    tester,
  ) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.interrupted)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_reuseFolderBtn), findsOneWidget);
  });

  testWidgets('shows reuse-folder button for failed batch', (tester) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.failed)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_reuseFolderBtn), findsOneWidget);
  });

  testWidgets('shows reuse-folder button for cancelled batch', (tester) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.cancelled)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_reuseFolderBtn), findsOneWidget);
  });

  testWidgets('does NOT show reuse-folder button for completed batch', (
    tester,
  ) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.completed)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_reuseFolderBtn), findsNothing);
  });

  testWidgets('reuse-folder button fires callback with source folder', (
    tester,
  ) async {
    String? captured;
    final bloc = _buildBloc([
      _batch(status: ImportBatchStatus.interrupted, folder: r'C:\legal_docs'),
    ]);
    addTearDown(bloc.close);

    await _pump(tester, bloc, onReuseFolder: (f) => captured = f);

    await tester.tap(find.text(_reuseFolderBtn));
    await tester.pumpAndSettle();

    expect(captured, r'C:\legal_docs');
  });

  testWidgets('does NOT show interrupted note for failed batch', (
    tester,
  ) async {
    final bloc = _buildBloc([_batch(status: ImportBatchStatus.failed)]);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text(_interruptedNote), findsNothing);
  });
}
