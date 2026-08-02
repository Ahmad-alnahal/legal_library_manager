// test/features/file_open/file_open_audit_integration_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/file_open/application/open_file_use_case.dart';
import 'package:legal_library_manager/features/file_open/data/repositories/drift_file_open_repository.dart';
import 'package:legal_library_manager/features/file_open/domain/services/file_existence_checker.dart';
import 'package:legal_library_manager/features/file_open/domain/services/os_file_opener.dart';
import 'package:legal_library_manager/features/file_open/presentation/bloc/file_open_bloc.dart';
import 'package:legal_library_manager/features/file_open/presentation/widgets/file_open_feedback.dart';
import 'package:legal_library_manager/features/file_open/presentation/widgets/open_actions.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

/// Existence checker that always reports a healthy regular file, so the test
/// never touches the real filesystem.
class _AlwaysRegularFile implements FileExistenceChecker {
  const _AlwaysRegularFile();
  @override
  FileExistenceStatus checkFile(String absolutePath) =>
      FileExistenceStatus.regularFile;
}

/// OS opener that records calls and always succeeds — never launches a real
/// external application.
class _FakeOpener implements OsFileOpener {
  int openFileCount = 0;
  int openFolderCount = 0;

  @override
  Future<OsOpenResult> openFile(String absolutePath) async {
    openFileCount++;
    return const OsOpenSuccess();
  }

  @override
  Future<OsOpenResult> openFolder(String absolutePath) async {
    openFolderCount++;
    return const OsOpenSuccess();
  }
}

class _FixedClock extends Clock {
  const _FixedClock();
  static const String iso = '2026-06-10T12:00:00.000Z';
  @override
  DateTime nowUtc() => DateTime.parse(iso);
}

Future<int> _insertDocument(AppDatabase db) => db
    .into(db.documents)
    .insert(
      DocumentsCompanion.insert(
        createdAt: '2026-06-10T00:00:00.000Z',
        updatedAt: '2026-06-10T00:00:00.000Z',
      ),
    );

Future<int> _insertFile(AppDatabase db, int documentId) => db
    .into(db.documentFiles)
    .insert(
      DocumentFilesCompanion.insert(
        documentId: documentId,
        fileRoleKey: FileRoleKey.sourceOriginal,
        fileName: 'sample.pdf',
        absolutePath: r'C:\Library\sample.pdf',
        extension: '.pdf',
        fileSizeBytes: 1024,
        createdAt: '2026-06-10T00:00:00.000Z',
        updatedAt: '2026-06-10T00:00:00.000Z',
        fileHealthKey: const Value(FileHealthKey.healthy),
      ),
    );

Future<void> _pumpActions(WidgetTester tester, FileOpenBloc bloc, int fileId) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: BlocProvider<FileOpenBloc>.value(
            value: bloc,
            child: FileOpenFeedbackListener(
              child: OpenActions(fileId: fileId, showOpenFile: true),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late AppDatabase db;
  late _FakeOpener opener;
  late FileOpenBloc bloc;

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    opener = _FakeOpener();
    final useCase = OpenFileUseCase(
      repository: DriftFileOpenRepository(db, const _FixedClock()),
      existenceChecker: const _AlwaysRegularFile(),
      osOpener: opener,
    );
    bloc = FileOpenBloc(useCase);
  });

  tearDown(() async {
    await bloc.close();
    await db.close();
  });

  testWidgets(
    'a UI-triggered successful file open records a succeeded file_open_event',
    (tester) async {
      final docId = await _insertDocument(db);
      final fileId = await _insertFile(db, docId);

      await _pumpActions(tester, bloc, fileId);

      await tester.tap(find.byKey(Key('open_file_button_$fileId')));
      await tester.pump(); // process gesture

      // Drift DB operations run on the real async event loop; runAsync lets them
      // complete outside of FakeAsync before we assert.
      await tester.runAsync(() => bloc.stream.firstWhere((s) => s.isTerminal));
      await tester.pumpAndSettle(); // settle UI + BlocListener snackbar

      expect(opener.openFileCount, 1);

      final events = await db.select(db.fileOpenEvents).get();
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.fileId, fileId);
      expect(event.documentId, docId);
      expect(event.openTargetKey, 'file');
      expect(event.resultKey, 'succeeded');
      expect(event.errorCode, isNull);
      expect(event.createdAt, _FixedClock.iso);

      // Confirms feedback was shown and no real application was launched.
      expect(find.text('تم فتح الملف.'), findsOneWidget);
      await _flushSnackBar(tester);
    },
  );

  testWidgets('a UI-triggered folder reveal records a succeeded folder event', (
    tester,
  ) async {
    final docId = await _insertDocument(db);
    final fileId = await _insertFile(db, docId);

    await _pumpActions(tester, bloc, fileId);

    await tester.tap(find.byKey(Key('open_folder_button_$fileId')));
    await tester.pump(); // process gesture
    await tester.runAsync(() => bloc.stream.firstWhere((s) => s.isTerminal));
    await tester.pumpAndSettle(); // settle UI + BlocListener snackbar

    expect(opener.openFolderCount, 1);

    final events = await db.select(db.fileOpenEvents).get();
    expect(events, hasLength(1));
    expect(events.single.openTargetKey, 'folder');
    expect(events.single.resultKey, 'succeeded');
    await _flushSnackBar(tester);
  });
}

/// Advances past the SnackBar auto-dismiss timer so no timer outlives the test.
Future<void> _flushSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}
