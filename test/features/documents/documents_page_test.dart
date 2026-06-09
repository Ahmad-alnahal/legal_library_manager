import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_item.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_query.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_list_repository.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/document_list_bloc.dart';
import 'package:legal_library_manager/features/documents/presentation/pages/documents_page.dart';
import 'package:legal_library_manager/features/reference/domain/entities/document_type_ref.dart';
import 'package:legal_library_manager/features/reference/domain/entities/main_category_ref.dart';
import 'package:legal_library_manager/features/reference/domain/entities/reference_item.dart';
import 'package:legal_library_manager/features/reference/domain/entities/sub_category_ref.dart';
import 'package:legal_library_manager/features/reference/domain/repositories/reference_repository.dart';

void main() {
  late FakeDocumentRepository documents;

  setUp(() async {
    await getIt.reset();
    documents = FakeDocumentRepository();
    getIt
      ..registerSingleton<DocumentListRepository>(documents)
      ..registerSingleton<ReferenceRepository>(FakeReferenceRepository())
      ..registerFactory<DocumentListBloc>(
        () => DocumentListBloc(
          repository: documents,
          pageSize: 2,
          searchDebounce: const Duration(milliseconds: 10),
        ),
      );
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
    expect(documents.queries.last.filters.workflowStatusKey, 'classified');

    await tester.tap(find.text('مسح الكل'));
    await tester.pumpAndSettle();
    expect(documents.queries.last.filters.workflowStatusKey, isNull);
  });

  testWidgets('expands source details without an open-file action', (
    tester,
  ) async {
    await pumpDocuments(tester);

    await tester.tap(find.byKey(const Key('document_row_1')));
    await tester.pumpAndSettle();

    expect(find.text('source.pdf'), findsOneWidget);
    expect(find.text(r'D:\source\source.pdf'), findsOneWidget);
    expect(find.textContaining('مصدر للقراءة فقط'), findsOneWidget);
    expect(find.textContaining('فتح الملف'), findsNothing);
  });

  testWidgets('selection and pagination retain loaded rows', (tester) async {
    await pumpDocuments(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('تم تحديد 1 مستند'), findsOneWidget);

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

    await tester.tap(find.text('التصفية'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
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
      workflowStatusKey: 'classified',
      trustLevelKey: 'trusted',
      metadataQualityKey: 'verified',
      fileCount: 1,
      hasDuplicate: true,
      hasCorruptedFile: false,
      hasUnreadableFile: false,
      updatedAt: '2026-06-09',
    ),
    DocumentListItem(
      id: 2,
      sourceFileName: 'الوثيقة الثانية.pdf',
      workflowStatusKey: 'needs_review',
      trustLevelKey: 'unverified',
      metadataQualityKey: 'low',
      fileCount: 1,
      hasDuplicate: false,
      hasCorruptedFile: true,
      hasUnreadableFile: false,
      updatedAt: '2026-06-08',
    ),
    DocumentListItem(
      id: 3,
      title: 'الوثيقة الثالثة',
      workflowStatusKey: 'imported',
      trustLevelKey: 'unverified',
      metadataQualityKey: 'low',
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
    return const [
      DocumentSourceFileItem(
        id: 1,
        fileName: 'source.pdf',
        absolutePath: r'D:\source\source.pdf',
        fileRoleKey: 'source_original',
        fileHealthKey: 'healthy',
        fileSizeBytes: 2048,
        isReadOnlySource: true,
      ),
    ];
  }
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
