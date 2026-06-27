// test/features/import/import_page_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/core/widgets/status_chip.dart';
import 'package:legal_library_manager/features/import/application/folder_picker.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/application/import_job_service.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_health_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/domain/repositories/import_repository.dart';
import 'package:legal_library_manager/features/import/presentation/bloc/import_bloc.dart';
import 'package:legal_library_manager/features/import/presentation/pages/import_page.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

import 'support/import_fakes.dart';

// Stable Arabic strings (mirror lib/l10n/app_ar.arb).
const String _startButton = 'بدء الفحص والاستيراد';
const String _pickButton = 'اختيار مجلد';
const String _emptyFolder = 'لم يتم اختيار مجلد بعد';
const String _summaryNew = 'مستندات جديدة';
const String _retryButton = 'إعادة محاولة الملفات المتعذّرة';
const String _resetButton = 'استيراد جديد';
const String _progressTitle = 'تقدم الاستيراد';
const String _cancelButton = 'إلغاء';

void main() {
  late AppDatabase db;
  late DriftImportRepository repo;

  const valid = FolderValidationResult.valid(r'C:\src');
  final provider = FakeProtectedRootsProvider(
    const ProtectedRoots(databaseRoot: r'C:\db'),
  );

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftImportRepository(db);
  });

  tearDown(() => db.close());

  ImportBloc buildBloc({
    required FakePdfScanner scanner,
    required FakeFileHasher hasher,
    FakeFolderValidator? validator,
    FakePdfHealthInspector? inspector,
    ImportRepository? repository,
  }) {
    final ImportRepository r = repository ?? repo;
    final service = ImportJobService(
      coordinator: ImportCoordinator(
        validator: validator ?? FakeFolderValidator(valid),
        scanner: scanner,
        hasher: hasher,
        inspector: inspector ?? FakePdfHealthInspector(),
        repository: r,
        clock: const SystemClock(),
        runner: syncRunner,
      ),
      protectedRootsProvider: provider,
      repository: r,
      clock: const SystemClock(),
    );
    return ImportBloc(jobService: service);
  }

  Future<void> pumpView(
    WidgetTester tester,
    ImportBloc bloc, {
    Size size = const Size(1280, 800),
    String? pickerPath,
    FolderPicker? picker,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: BlocProvider<ImportBloc>.value(
            value: bloc,
            child: ImportView(picker: picker ?? FakeFolderPicker(pickerPath)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('idle screen shows source controls and a disabled start', (
    tester,
  ) async {
    final bloc = buildBloc(
      scanner: FakePdfScanner(const PdfScanResult(candidates: [])),
      hasher: FakeFileHasher(),
    );
    addTearDown(bloc.close);

    await pumpView(tester, bloc);

    expect(find.text(_pickButton), findsOneWidget);
    expect(find.text(_emptyFolder), findsOneWidget);
    expect(find.text(_startButton), findsOneWidget);
    // Start is disabled until a folder is selected.
    final FilledButton start = tester.widget(
      find.widgetWithText(FilledButton, _startButton),
    );
    expect(start.onPressed, isNull);
  });

  testWidgets('completed report shows summary, file rows, retry and reset', (
    tester,
  ) async {
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(
          candidates: [candidate(r'C:\src\a.pdf'), candidate(r'C:\src\d.pdf')],
        ),
      ),
      hasher: FakeFileHasher(failures: {r'C:\src\d.pdf'}),
    );
    addTearDown(bloc.close);

    await pumpView(tester, bloc);
    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isTerminal);
    await tester.pumpAndSettle();

    expect(find.text(_summaryNew), findsOneWidget);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('d.pdf'), findsOneWidget);
    // A retryable failure exists -> retry + reset are offered.
    expect(find.text(_retryButton), findsOneWidget);
    expect(find.text(_resetButton), findsOneWidget);
  });

  testWidgets('active run shows progress and a cancel action', (tester) async {
    final gate = Completer<void>();
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(gate: gate),
    );
    addTearDown(bloc.close);

    await pumpView(tester, bloc);
    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isActive);
    await tester.pump();

    expect(find.text(_progressTitle), findsOneWidget);
    expect(find.text(_cancelButton), findsOneWidget);

    gate.complete();
    await bloc.stream.firstWhere((s) => s.isTerminal);
    await tester.pumpAndSettle();
  });

  testWidgets('picking a folder selects it without scanning', (tester) async {
    final scanner = FakePdfScanner(const PdfScanResult(candidates: []));
    final bloc = buildBloc(scanner: scanner, hasher: FakeFileHasher());
    addTearDown(bloc.close);

    await pumpView(tester, bloc, pickerPath: r'C:\chosen');
    await tester.tap(find.text(_pickButton));
    await tester.pumpAndSettle();

    // The folder path is shown; nothing was scanned.
    expect(find.text(r'C:\chosen'), findsOneWidget);
    expect(scanner.calls, 0);
    // Start is now enabled.
    final FilledButton start = tester.widget(
      find.widgetWithText(FilledButton, _startButton),
    );
    expect(start.onPressed, isNotNull);
  });

  for (final Size size in const [
    Size(1280, 800),
    Size(1024, 700),
    Size(800, 600),
    Size(640, 600),
  ]) {
    testWidgets('completed report is overflow-free at $size', (tester) async {
      final bloc = buildBloc(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [
              candidate(r'C:\src\a.pdf'),
              candidate(r'C:\src\b.pdf'),
              candidate(r'C:\src\d.pdf'),
            ],
          ),
        ),
        hasher: FakeFileHasher(failures: {r'C:\src\d.pdf'}),
      );
      addTearDown(bloc.close);

      await pumpView(tester, bloc, size: size);
      bloc.add(const ImportFolderSelected(r'C:\src'));
      bloc.add(const ImportStartRequested());
      await bloc.stream.firstWhere((s) => s.isTerminal);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'overflow @ $size');
    });
  }

  testWidgets('validation failure shows its specific protected-folder message', (
    tester,
  ) async {
    final bloc = buildBloc(
      scanner: FakePdfScanner(const PdfScanResult(candidates: [])),
      hasher: FakeFileHasher(),
      validator: FakeFolderValidator(
        const FolderValidationResult(
          code: FolderValidationCode.insideProtectedRoot,
        ),
      ),
    );
    addTearDown(bloc.close);

    await pumpView(tester, bloc);
    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isTerminal);
    await tester.pumpAndSettle();

    // The specific validation message is shown — not an empty results section.
    expect(find.text('المجلد يقع داخل مجلد محمي تابع للنظام.'), findsOneWidget);
    expect(find.text('نتائج الملفات'), findsNothing);
  });

  testWidgets('failed run with partial results shows banner and the results', (
    tester,
  ) async {
    // completeBatch throws after one file imported -> failed report with files.
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(),
      repository: FakeImportRepository(failOnComplete: true),
    );
    addTearDown(bloc.close);

    await pumpView(tester, bloc);
    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isTerminal);
    await tester.pumpAndSettle();

    expect(bloc.state.status, ImportStatus.failed);
    // Both the failure banner and the partial per-file result are shown.
    expect(find.text('تعذّر الاستيراد'), findsOneWidget);
    expect(find.text('نتائج الملفات'), findsOneWidget);
    expect(find.text('a.pdf'), findsOneWidget);
  });

  testWidgets('large report scrolls safely and only builds visible rows', (
    tester,
  ) async {
    const int total = 2000;
    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(
          candidates: [
            for (int i = 0; i < total; i++) candidate('C:\\src\\f$i.pdf'),
          ],
        ),
      ),
      hasher: FakeFileHasher(),
      repository: FakeImportRepository(),
    );
    addTearDown(bloc.close);

    await pumpView(tester, bloc);
    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isTerminal);
    await tester.pumpAndSettle();

    expect(bloc.state.report!.files.length, total);
    // The list is virtualized: only a small visible subset of rows (one
    // StatusChip each) is built, far fewer than the 2000 reported files.
    final int builtRows = find.byType(StatusChip).evaluate().length;
    expect(builtRows, greaterThan(0));
    expect(builtRows, lessThan(100));
    expect(tester.takeException(), isNull);

    final Finder resultsList = find.byType(ListView);
    expect(resultsList, findsOneWidget);
    expect(find.text('f0.pdf'), findsOneWidget);

    await tester.ensureVisible(resultsList);
    await tester.pumpAndSettle();
    await tester.drag(resultsList, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('f0.pdf'), findsNothing);
    expect(find.byType(StatusChip).evaluate().length, lessThan(100));
    expect(tester.takeException(), isNull);

    // Disposing after interaction must also release the shared controller
    // without a late Scrollbar/ScrollPosition exception.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a native picker failure does not crash and selects nothing', (
    tester,
  ) async {
    final scanner = FakePdfScanner(const PdfScanResult(candidates: []));
    final bloc = buildBloc(scanner: scanner, hasher: FakeFileHasher());
    addTearDown(bloc.close);

    await pumpView(
      tester,
      bloc,
      picker: FakeFolderPicker(null, throwOnPick: true),
    );
    await tester.tap(find.text(_pickButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_emptyFolder), findsOneWidget);
    expect(scanner.calls, 0);
  });

  testWidgets('cancelling the picker selects nothing and never scans', (
    tester,
  ) async {
    final scanner = FakePdfScanner(const PdfScanResult(candidates: []));
    final bloc = buildBloc(scanner: scanner, hasher: FakeFileHasher());
    addTearDown(bloc.close);

    await pumpView(tester, bloc, picker: FakeFolderPicker(null));
    await tester.tap(find.text(_pickButton));
    await tester.pumpAndSettle();

    expect(find.text(_emptyFolder), findsOneWidget);
    expect(scanner.calls, 0);
  });

  testWidgets(
    'picker returning after the bloc is closed does not throw',
    (tester) async {
      final gate = Completer<String?>();
      final scanner = FakePdfScanner(const PdfScanResult(candidates: []));
      final bloc = buildBloc(scanner: scanner, hasher: FakeFileHasher());

      await pumpView(tester, bloc, picker: FakeFolderPicker(null, gate: gate));
      await tester.tap(find.text(_pickButton));
      await tester.pump();

      // Dispose while the native dialog is still "open". Don't await close()
      // here: the picker future is still pending, so let the disposal settle via
      // pumps instead.
      unawaited(bloc.close());
      await tester.pump();
      expect(bloc.isClosed, isTrue);

      // The dialog now returns a selection after disposal: the guarded handler
      // must not add an event to the closed BLoC or throw.
      gate.complete(r'C:\late');
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(scanner.calls, 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('corrupted file shows Arabic corrupted status chip', (
    tester,
  ) async {
    const String corruptedLabel = 'ملف تالف';
    const String failedSummaryLabel = 'ملفات متعذّرة';

    final bloc = buildBloc(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\broken.pdf')]),
      ),
      hasher: FakeFileHasher(),
      inspector: FakePdfHealthInspector(
        byPath: {
          r'C:\src\broken.pdf': const PdfHealthResult(
            status: PdfHealthStatus.corrupted,
            sizeBytes: 0,
          ),
        },
      ),
      repository: FakeImportRepository(),
    );
    addTearDown(bloc.close);

    await pumpView(tester, bloc);
    bloc.add(const ImportFolderSelected(r'C:\src'));
    bloc.add(const ImportStartRequested());
    await bloc.stream.firstWhere((s) => s.isTerminal);
    await tester.pumpAndSettle();

    // The Arabic corrupted label appears as a StatusChip.
    expect(find.text(corruptedLabel), findsWidgets);
    // The summary shows 1 failed file.
    expect(find.text(failedSummaryLabel), findsOneWidget);
    // No successful new imports.
    expect(bloc.state.report!.importedNewCount, 0);
    expect(bloc.state.report!.failedCount, 1);
  });
}
