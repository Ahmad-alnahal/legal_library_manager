import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_item.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_query.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_list_repository.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/document_list_bloc.dart';
import 'package:legal_library_manager/features/documents/presentation/pages/documents_page.dart';
import 'package:legal_library_manager/features/file_open/application/open_file_use_case.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_file_result.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_target.dart';
import 'package:legal_library_manager/features/file_open/domain/repositories/file_open_repository.dart';
import 'package:legal_library_manager/features/file_open/domain/services/file_existence_checker.dart';
import 'package:legal_library_manager/features/file_open/domain/services/os_file_opener.dart';
import 'package:legal_library_manager/features/file_open/presentation/bloc/file_open_bloc.dart';
import 'package:legal_library_manager/features/reference/domain/entities/document_type_ref.dart';
import 'package:legal_library_manager/features/reference/domain/entities/main_category_ref.dart';
import 'package:legal_library_manager/features/reference/domain/entities/reference_item.dart';
import 'package:legal_library_manager/features/reference/domain/entities/sub_category_ref.dart';
import 'package:legal_library_manager/features/reference/domain/repositories/reference_repository.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

void main() {
  late FakeDocumentRepository documents;
  late FakeOpenFileUseCase openFile;

  setUp(() async {
    await getIt.reset();
    documents = FakeDocumentRepository();
    openFile = FakeOpenFileUseCase();
    getIt
      ..registerSingleton<DocumentListRepository>(documents)
      ..registerSingleton<ReferenceRepository>(FakeReferenceRepository())
      ..registerFactory<DocumentListBloc>(
        () => DocumentListBloc(
          repository: documents,
          pageSize: 2,
          searchDebounce: const Duration(milliseconds: 10),
        ),
      )
      ..registerFactory<FileOpenBloc>(() => FileOpenBloc(openFile));
  });

  tearDown(() => getIt.reset());

  testWidgets('loads, searches, sorts, filters, and clears filters', (
    tester,
  ) async {
    await pumpDocuments(tester);

    expect(find.text('وثيقة قانونية'), findsOneWidget);
    expect(find.textContaining('النتائج: 3'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'قانون');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(documents.queries.last.filters.search, 'قانون');

    await tester.tap(find.text('الأحدث تحديثًا'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العنوان: أ - ي').last);
    await tester.pumpAndSettle();
    expect(documents.queries.last.sort, DocumentListSort.titleAscending);

    await tester.tap(find.text('التصفية'));
    await tester.pumpAndSettle();
    expect(find.text('عوامل التصفية'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مصنف').last);
    await tester.pumpAndSettle();
    expect(
      documents.queries.last.filters.workflowStatusKey,
      WorkflowStatusKey.classified,
    );

    await tester.tap(find.text('مسح الكل'));
    await tester.pumpAndSettle();
    expect(documents.queries.last.filters.workflowStatusKey, isNull);
  });

  testWidgets('expands source details with safe open actions only', (
    tester,
  ) async {
    await pumpDocuments(tester);

    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    expect(find.text('source.pdf'), findsOneWidget);
    expect(find.text(r'D:\source\source.pdf'), findsOneWidget);
    expect(find.textContaining('مصدر للقراءة فقط'), findsOneWidget);

    // Separate Open File and Open Folder actions exist, keyed by the DB id.
    expect(find.byKey(const Key('open_file_button_1')), findsOneWidget);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);

    // No source-file mutation actions are present (checked as button labels so
    // descriptive safety copy never produces a false match).
    expect(find.widgetWithText(TextButton, 'حذف الملف'), findsNothing);
    expect(find.widgetWithText(TextButton, 'نقل الملف'), findsNothing);
    expect(find.widgetWithText(TextButton, 'إعادة تسمية الملف'), findsNothing);
    expect(find.widgetWithText(TextButton, 'استبدال الملف'), findsNothing);
  });

  testWidgets('tapping Open File sends the DB file id and file target', (
    tester,
  ) async {
    await pumpDocuments(tester);
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_file_button_1')));
    await tester.pumpAndSettle();

    expect(openFile.calls, [(fileId: 1, target: OpenTarget.file)]);
    expect(find.text('تم فتح الملف.'), findsOneWidget);
    await _flushSnackBar(tester);
  });

  testWidgets('tapping Open Folder sends the DB file id and folder target', (
    tester,
  ) async {
    await pumpDocuments(tester);
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_folder_button_1')));
    await tester.pumpAndSettle();

    expect(openFile.calls, [(fileId: 1, target: OpenTarget.folder)]);
    expect(find.text('تم فتح مجلد الملف.'), findsOneWidget);
    await _flushSnackBar(tester);
  });

  testWidgets('a blocked open shows the mapped Arabic error', (tester) async {
    openFile.result = const OpenFileBlocked(
      code: FileOpenError.unsupportedExtension,
      safeMessage: 'unused',
    );
    await pumpDocuments(tester);
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_file_button_1')));
    await tester.pumpAndSettle();

    expect(
      find.text('نوع الملف غير مدعوم أو لا يطابق الامتداد المسجل.'),
      findsOneWidget,
    );
    await _flushSnackBar(tester);
  });

  testWidgets('only the active action loads and overlapping taps are dropped', (
    tester,
  ) async {
    openFile.gate = Completer<OpenFileResult>();
    await pumpDocuments(tester);
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_file_button_1')));
    await tester.pump(); // enter opening state, do not settle (gate pending)
    await tester.pump(); // let the bloc state reach the BlocBuilder

    // The active (file) action shows a spinner.
    expect(
      find.descendant(
        of: find.byKey(const Key('open_file_button_1')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    // The folder action is disabled while busy. (TextButton.icon yields a
    // TextButton subclass, so match by predicate, not exact type.)
    final folderButton = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(const Key('open_folder_button_1')),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
    expect(folderButton.onPressed, isNull);

    // A second tap on the folder action while busy is ignored.
    await tester.tap(
      find.byKey(const Key('open_folder_button_1')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(openFile.calls, [(fileId: 1, target: OpenTarget.file)]);

    openFile.gate!.complete(const OpenFileSuccess(target: OpenTarget.file));
    await tester.pumpAndSettle();
    await _flushSnackBar(tester);
  });

  testWidgets('pagination retains loaded rows', (tester) async {
    await pumpDocuments(tester);

    await tester.tap(find.text('تحميل المزيد'));
    await tester.pumpAndSettle();
    expect(find.text('الوثيقة الثالثة'), findsOneWidget);
    expect(find.textContaining('المعروض: 3'), findsOneWidget);
  });

  testWidgets('renders without overflow at minimum supported size', (
    tester,
  ) async {
    await pumpDocuments(tester, size: const Size(640, 600));
    expect(tester.takeException(), isNull);

    // Expanding a row exercises the source-file open actions at the minimum
    // supported width without overflow.
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open_file_button_1')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('التصفية'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // Health-based Open File visibility
  // ---------------------------------------------------------------------------

  testWidgets('healthy file shows both Open File and Open Folder buttons', (
    tester,
  ) async {
    // Default health is 'healthy'; no override needed.
    await pumpDocuments(tester);
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_file_button_1')), findsOneWidget);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
  });

  testWidgets(
    'corrupted file hides Open File button but shows Open Folder button',
    (tester) async {
      documents.sourceFileHealthKey = FileHealthKey.corrupted;
      await pumpDocuments(tester);
      await tester.tap(find.byKey(const Key('document_row_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open_file_button_1')), findsNothing);
      expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
    },
  );

  testWidgets(
    'unreadable file hides Open File button but shows Open Folder button',
    (tester) async {
      documents.sourceFileHealthKey = FileHealthKey.unreadable;
      await pumpDocuments(tester);
      await tester.tap(find.byKey(const Key('document_row_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open_file_button_1')), findsNothing);
      expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
    },
  );

  testWidgets('missing health hides Open File button', (tester) async {
    documents.sourceFileHealthKey = FileHealthKey.missing;
    await pumpDocuments(tester);
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_file_button_1')), findsNothing);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
  });

  testWidgets('unknown health hides Open File button', (tester) async {
    documents.sourceFileHealthKey = FileHealthKey.unknown;
    await pumpDocuments(tester);
    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_file_button_1')), findsNothing);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
  });
}

/// Advances past the SnackBar auto-dismiss timer so no timer outlives the test.
Future<void> _flushSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> pumpDocuments(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    const MaterialApp(
      locale: Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: DocumentsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeDocumentRepository implements DocumentListRepository {
  final queries = <DocumentListQuery>[];

  /// Override per-test to exercise non-healthy health visibility.
  String sourceFileHealthKey = FileHealthKey.healthy;

  final allItems = const [
    DocumentListItem(
      id: 1,
      documentCode: 'DOC-0001',
      title: 'وثيقة قانونية',
      documentTypeId: 1,
      documentTypeNameAr: 'كتاب',
      primaryMainCategoryId: 1,
      primaryMainCategoryNameAr: 'القانون العام',
      primarySubCategoryId: 10,
      primarySubCategoryNameAr: 'القانون الدستوري',
      countryKey: 'ps',
      workflowStatusKey: WorkflowStatusKey.classified,
      trustLevelKey: TrustLevelKey.trusted,
      metadataQualityKey: MetadataQualityKey.verified,
      fileCount: 1,
      hasDuplicate: true,
      hasCorruptedFile: false,
      hasUnreadableFile: false,
      updatedAt: '2026-06-09',
    ),
    DocumentListItem(
      id: 2,
      sourceFileName: 'الوثيقة الثانية.pdf',
      workflowStatusKey: WorkflowStatusKey.needsReview,
      trustLevelKey: TrustLevelKey.unverified,
      metadataQualityKey: MetadataQualityKey.low,
      fileCount: 1,
      hasDuplicate: false,
      hasCorruptedFile: true,
      hasUnreadableFile: false,
      updatedAt: '2026-06-08',
    ),
    DocumentListItem(
      id: 3,
      title: 'الوثيقة الثالثة',
      workflowStatusKey: WorkflowStatusKey.imported,
      trustLevelKey: TrustLevelKey.unverified,
      metadataQualityKey: MetadataQualityKey.low,
      fileCount: 1,
      hasDuplicate: false,
      hasCorruptedFile: false,
      hasUnreadableFile: true,
      updatedAt: '2026-06-07',
    ),
  ];

  @override
  Future<DocumentListPage> getDocuments(DocumentListQuery query) async {
    queries.add(query);
    final end = (query.offset + query.limit).clamp(0, allItems.length);
    return DocumentListPage(
      items: allItems.sublist(query.offset.clamp(0, allItems.length), end),
      totalCount: allItems.length,
      offset: query.offset,
      limit: query.limit,
    );
  }

  @override
  Future<List<DocumentSourceFileItem>> getSourceFiles(int documentId) async {
    return [
      DocumentSourceFileItem(
        id: 1,
        fileName: 'source.pdf',
        absolutePath: r'D:\source\source.pdf',
        fileRoleKey: FileRoleKey.sourceOriginal,
        fileHealthKey: sourceFileHealthKey,
        fileSizeBytes: 2048,
        isReadOnlySource: true,
      ),
    ];
  }

  @override
  Future<void> setPreferredSourceFile(int documentId, int fileId) async {}
}

class FakeReferenceRepository implements ReferenceRepository {
  static const generic = [
    ReferenceItem(
      key: 'classified',
      nameAr: 'مصنف',
      nameEn: 'Classified',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getCountries() async => const [
    ReferenceItem(
      key: 'ps',
      nameAr: 'فلسطين',
      nameEn: 'Palestine',
      sortOrder: 1,
    ),
  ];

  @override
  Future<ReferenceItem?> getCountryByKey(String key) async =>
      (await getCountries()).first;

  @override
  Future<List<DocumentTypeRef>> getDocumentTypes() async => const [
    DocumentTypeRef(
      id: 1,
      key: 'book',
      nameAr: 'كتاب',
      nameEn: 'Book',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getFileHealthStatuses() async => generic;

  @override
  Future<List<ReferenceItem>> getFileRoles() async => generic;

  @override
  Future<List<ReferenceItem>> getLanguages() async => generic;

  @override
  Future<List<MainCategoryRef>> getMainCategories() async => const [
    MainCategoryRef(
      id: 1,
      key: 'public_law',
      nameAr: 'القانون العام',
      nameEn: 'Public Law',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getMetadataQualities() async => generic;

  @override
  Future<List<SubCategoryRef>> getSubCategories({
    int? mainCategoryId,
    String? mainCategoryKey,
  }) async => const [
    SubCategoryRef(
      id: 10,
      mainCategoryId: 1,
      key: 'constitutional',
      nameAr: 'القانون الدستوري',
      nameEn: 'Constitutional Law',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getTrustLevels() async => generic;

  @override
  Future<List<ReferenceItem>> getUsageRights() async => generic;

  @override
  Future<List<ReferenceItem>> getWorkflowStatuses() async => generic;
}

// --- safe-open test doubles -----------------------------------------------

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

/// Controllable [OpenFileUseCase] that records calls and never touches the OS.
class FakeOpenFileUseCase extends OpenFileUseCase {
  FakeOpenFileUseCase()
    : super(
        repository: _DummyRepo(),
        existenceChecker: _DummyChecker(),
        osOpener: _DummyOpener(),
      );

  final List<({int fileId, OpenTarget target})> calls = [];
  Completer<OpenFileResult>? gate;
  OpenFileResult result = const OpenFileSuccess(target: OpenTarget.file);

  @override
  Future<OpenFileResult> execute(int fileId, OpenTarget target) async {
    calls.add((fileId: fileId, target: target));
    final pending = gate;
    if (pending != null) {
      final gated = await pending.future;
      return _retarget(gated, target);
    }
    return _retarget(result, target);
  }

  /// Aligns the result's target with the requested target so success/audit
  /// feedback matches the action the user pressed.
  OpenFileResult _retarget(OpenFileResult value, OpenTarget target) {
    return switch (value) {
      OpenFileSuccess() => OpenFileSuccess(target: target),
      OpenFileAuditFailure() => OpenFileAuditFailure(target: target),
      _ => value,
    };
  }
}
