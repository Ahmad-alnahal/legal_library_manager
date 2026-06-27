// test/features/import/widgets/import_status_banner_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/application/import_job_service.dart';
import 'package:legal_library_manager/features/import/application/import_job_snapshot.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/presentation/bloc/import_status_bloc.dart';
import 'package:legal_library_manager/features/import/presentation/widgets/import_status_banner.dart';
import 'package:legal_library_manager/features/shell/domain/entities/app_section.dart';
import 'package:legal_library_manager/features/shell/presentation/bloc/navigation_bloc.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

import '../support/import_fakes.dart';

const _valid = FolderValidationResult.valid(r'C:\src');
final _provider = FakeProtectedRootsProvider(
  const ProtectedRoots(databaseRoot: r'C:\db'),
);

ImportJobService _makeService({
  FakePdfScanner? scanner,
  FakeFileHasher? hasher,
}) {
  return ImportJobService(
    coordinator: ImportCoordinator(
      validator: FakeFolderValidator(_valid),
      scanner: scanner ?? FakePdfScanner(const PdfScanResult(candidates: [])),
      hasher: hasher ?? FakeFileHasher(),
      inspector: FakePdfHealthInspector(),
      repository: FakeImportRepository(),
      clock: const SystemClock(),
      runner: syncRunner,
    ),
    protectedRootsProvider: _provider,
    repository: FakeImportRepository(),
    clock: const SystemClock(),
  );
}

/// Pumps the full test shell.
///
/// Uses explicit [pump] calls — [pumpAndSettle] hangs on Windows because the
/// Navigator's initial-route animation keeps scheduling frames indefinitely in
/// the test binding.
Future<void> _pumpApp(
  WidgetTester tester,
  ImportStatusBloc statusBloc,
  NavigationBloc navBloc,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ar'),
      home: MultiBlocProvider(
        providers: [BlocProvider<NavigationBloc>.value(value: navBloc)],
        child: Scaffold(body: ImportStatusBanner.withBloc(statusBloc)),
      ),
    ),
  );
  // Two pumps settle l10n loading and the initial frame render.
  await tester.pump();
  await tester.pump();
}

void main() {
  late NavigationBloc navBloc;

  setUp(() {
    navBloc = NavigationBloc();
  });

  tearDown(() {
    navBloc.close();
  });

  testWidgets('banner is hidden when service is idle', (tester) async {
    final service = _makeService();
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    await _pumpApp(tester, bloc, navBloc);

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('انتقل إلى الاستيراد'), findsNothing);
  });

  testWidgets('completed run shows banner with label and dismiss button', (
    tester,
  ) async {
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    // Start before pumping so the BLoC is already in completed state.
    service.start(folder: r'C:\src', recursive: true);

    await _pumpApp(tester, bloc, navBloc);

    expect(find.text('اكتمل الاستيراد'), findsOneWidget);
    expect(find.text('انتقل إلى الاستيراد'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('إلغاء الاستيراد'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('banner shows running state while gated hasher blocks', (
    tester,
  ) async {
    final gate = Completer<void>();
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
      hasher: FakeFileHasher(gate: gate),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    await _pumpApp(tester, bloc, navBloc);

    service.start(folder: r'C:\src', recursive: true);
    await tester.pump();
    await tester.pump();

    expect(find.text('جارٍ الاستيراد'), findsOneWidget);
    expect(find.text('انتقل إلى الاستيراد'), findsOneWidget);
    expect(find.text('إلغاء الاستيراد'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('اكتمل الاستيراد'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('cancel button forwards cancellation to service', (tester) async {
    final gate = Completer<void>();
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(
          candidates: [candidate(r'C:\src\a.pdf'), candidate(r'C:\src\b.pdf')],
        ),
      ),
      hasher: FakeFileHasher(gate: gate),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    await _pumpApp(tester, bloc, navBloc);

    service.start(folder: r'C:\src', recursive: true);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('إلغاء الاستيراد'));

    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(service.current.status, ImportJobStatus.cancelled);
    expect(find.text('تم إلغاء الاستيراد'), findsOneWidget);
  });

  testWidgets('dismiss button hides the terminal banner', (tester) async {
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    service.start(folder: r'C:\src', recursive: true);
    await _pumpApp(tester, bloc, navBloc);

    expect(find.text('اكتمل الاستيراد'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('اكتمل الاستيراد'), findsNothing);
  });

  testWidgets('"go to import" navigates to import section', (tester) async {
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    service.start(folder: r'C:\src', recursive: true);
    await _pumpApp(tester, bloc, navBloc);

    expect(navBloc.state.section, AppSection.dashboard);

    await tester.tap(find.text('انتقل إلى الاستيراد'));
    await tester.pump();

    expect(navBloc.state.section, AppSection.import);
  });

  testWidgets('banner reappears after dismiss on a second run', (tester) async {
    final service = _makeService(
      scanner: FakePdfScanner(
        PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
      ),
    );
    final bloc = ImportStatusBloc(jobService: service);
    addTearDown(bloc.close);
    addTearDown(service.dispose);

    service.start(folder: r'C:\src', recursive: true);
    await _pumpApp(tester, bloc, navBloc);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('اكتمل الاستيراد'), findsNothing);

    service.reset();
    await tester.pump();
    service.start(folder: r'C:\src', recursive: true);
    await tester.pump();
    await tester.pump();

    expect(find.text('اكتمل الاستيراد'), findsOneWidget);
  });
}
