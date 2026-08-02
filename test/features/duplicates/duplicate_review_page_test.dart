// test/features/duplicates/duplicate_review_page_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/duplicates/domain/entities/duplicate_group_details.dart';
import 'package:legal_library_manager/features/duplicates/domain/entities/duplicate_group_file_item.dart';
import 'package:legal_library_manager/features/duplicates/domain/entities/duplicate_group_summary.dart';
import 'package:legal_library_manager/features/duplicates/domain/repositories/duplicate_review_repository.dart';
import 'package:legal_library_manager/features/duplicates/presentation/bloc/duplicate_review_bloc.dart';
import 'package:legal_library_manager/features/duplicates/presentation/pages/duplicate_review_page.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

class _FakeRepository implements DuplicateReviewRepository {
  _FakeRepository({
    this.groups = const [],
    this.totalCount = 0,
    this.detailsMap = const {},
    this.throwOnGroups = false,
  });

  final List<DuplicateGroupSummary> groups;
  final int totalCount;
  final Map<int, DuplicateGroupDetails> detailsMap;
  final bool throwOnGroups;

  @override
  Future<DuplicateGroupPage> getGroups({int offset = 0, int limit = 50}) async {
    if (throwOnGroups) throw Exception('load error');
    return DuplicateGroupPage(
      groups: groups,
      totalCount: totalCount,
      pendingReviewCount: groups
          .where((group) => group.reviewStatusKey == 'unreviewed')
          .length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<DuplicateGroupDetails> getGroupDetails(int groupId) async {
    final d = detailsMap[groupId];
    if (d == null) throw StateError('not found: $groupId');
    return d;
  }

  @override
  Future<void> setPreferredMember({
    required int groupId,
    required int fileId,
  }) async {}

  @override
  Future<void> setMemberHidden({
    required int groupId,
    required int fileId,
    required bool hidden,
  }) async {}

  @override
  Future<void> updateReview({
    required int groupId,
    required String statusKey,
    String? notes,
  }) async {}
}

DuplicateGroupSummary _summary({
  int id = 1,
  String code = 'GRP-001',
  int members = 2,
  String displayName = 'Duplicate test document',
}) => DuplicateGroupSummary(
  id: id,
  groupCode: code,
  sha256Hash: 'a' * 64,
  reviewStatusKey: 'unreviewed',
  memberCount: members,
  displayName: displayName,
  createdAt: '2026-06-20T10:00:00.000Z',
  updatedAt: '2026-06-20T10:00:00.000Z',
);

DuplicateGroupFileItem _member({
  int fileId = 10,
  bool preferred = false,
  String title = 'وثيقة اختبار',
}) => DuplicateGroupFileItem(
  fileId: fileId,
  documentId: 1,
  documentTitle: title,
  fileName: 'test-$fileId.pdf',
  absolutePath: r'C:\source\test.pdf',
  fileRoleKey: FileRoleKey.sourceOriginal,
  fileHealthKey: FileHealthKey.healthy,
  fileSizeBytes: 2048,
  workflowStatusKey: WorkflowStatusKey.imported,
  isHiddenFromSearch: false,
  isPreferred: preferred,
  addedAt: '2026-06-20T10:00:00.000Z',
);

DuplicateGroupDetails _details(int id, [String? code]) => DuplicateGroupDetails(
  summary: _summary(id: id, code: code ?? 'GRP-$id'),
  members: [_member(fileId: 10, preferred: true), _member(fileId: 11)],
);

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeRepository repo, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await getIt.reset();
  getIt
    ..registerSingleton<DuplicateReviewRepository>(repo)
    ..registerFactory<DuplicateReviewBloc>(
      () => DuplicateReviewBloc(repository: repo, pageSize: 10),
    );

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
        child: Scaffold(body: DuplicateReviewPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => getIt.reset());

  testWidgets('renders safety banner on load', (tester) async {
    await _pumpPage(tester, _FakeRepository());

    expect(find.text('البيانات المصدرية محمية'), findsOneWidget);
    expect(
      find.textContaining('لا يُحذف أو يُعدّل أو يُنقل أي ملف أصلي'),
      findsOneWidget,
    );
  });

  testWidgets('shows empty state when no duplicate groups exist', (
    tester,
  ) async {
    await _pumpPage(tester, _FakeRepository());

    expect(find.text('لا توجد مجموعات تكرار'), findsOneWidget);
  });

  testWidgets('shows group list when groups are returned', (tester) async {
    final repo = _FakeRepository(
      groups: [
        _summary(id: 1, code: 'GRP-001', displayName: 'First duplicate'),
        _summary(id: 2, code: 'GRP-002', displayName: 'Second duplicate'),
      ],
      totalCount: 2,
    );

    await _pumpPage(tester, repo);

    expect(find.text('First duplicate'), findsOneWidget);
    expect(find.text('Second duplicate'), findsOneWidget);
    expect(find.textContaining('GRP-001'), findsOneWidget);
    expect(find.textContaining('GRP-002'), findsOneWidget);
  });

  testWidgets('shows prompt to select group in detail panel initially', (
    tester,
  ) async {
    final repo = _FakeRepository(groups: [_summary()], totalCount: 1);

    await _pumpPage(tester, repo);

    expect(find.textContaining('اختر مجموعة'), findsOneWidget);
  });

  testWidgets('selecting a group loads and shows its members', (tester) async {
    final repo = _FakeRepository(
      groups: [_summary(id: 1, code: 'GRP-001')],
      totalCount: 1,
      detailsMap: {1: _details(1, 'GRP-001')},
    );

    await _pumpPage(tester, repo);
    await tester.tap(find.text('Duplicate test document'));
    await tester.pumpAndSettle();

    expect(find.text('test-10.pdf'), findsOneWidget);
    expect(find.text('test-11.pdf'), findsOneWidget);
    expect(find.text('وثيقة اختبار'), findsWidgets);
  });

  testWidgets('preferred member shows preferred badge', (tester) async {
    final repo = _FakeRepository(
      groups: [_summary(id: 1, code: 'GRP-001')],
      totalCount: 1,
      detailsMap: {1: _details(1, 'GRP-001')},
    );

    await _pumpPage(tester, repo);
    await tester.tap(find.text('Duplicate test document'));
    await tester.pumpAndSettle();

    expect(find.text('مفضّل'), findsOneWidget);
  });

  testWidgets('shows error state when repository throws', (tester) async {
    await _pumpPage(tester, _FakeRepository(throwOnGroups: true));

    expect(find.text('تعذّر تحميل مجموعات التكرار'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('metadata-only duplicate decision controls are visible', (
    tester,
  ) async {
    final repo = _FakeRepository(
      groups: [_summary(id: 1, code: 'GRP-001')],
      totalCount: 1,
      detailsMap: {1: _details(1, 'GRP-001')},
    );

    await _pumpPage(tester, repo);
    await tester.tap(find.text('Duplicate test document'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsWidgets);
  });

  testWidgets('no destructive action buttons are present', (tester) async {
    final repo = _FakeRepository(
      groups: [_summary(id: 1, code: 'GRP-001')],
      totalCount: 1,
      detailsMap: {1: _details(1, 'GRP-001')},
    );

    await _pumpPage(tester, repo);
    await tester.tap(find.text('Duplicate test document'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'حذف'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'نقل'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'دمج'), findsNothing);
    expect(find.widgetWithText(TextButton, 'حذف الملف'), findsNothing);
    expect(find.widgetWithText(TextButton, 'نقل الملف'), findsNothing);
    expect(find.widgetWithText(TextButton, 'إعادة تسمية'), findsNothing);
  });

  testWidgets('renders without overflow at minimum supported size', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _FakeRepository(groups: [_summary(id: 1)], totalCount: 1),
      size: const Size(640, 600),
    );

    expect(tester.takeException(), isNull);
  });
}
