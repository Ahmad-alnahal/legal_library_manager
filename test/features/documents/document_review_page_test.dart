import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/core/validation/validation_error.dart';
import 'package:legal_library_manager/core/validation/validation_result.dart';
import 'package:legal_library_manager/features/categories/domain/entities/managed_main_category.dart';
import 'package:legal_library_manager/features/categories/domain/entities/managed_sub_category.dart';
import 'package:legal_library_manager/features/categories/domain/repositories/category_management_repository.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_aggregate.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_classification_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_common_metadata.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_item.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_query.dart';
import 'package:legal_library_manager/features/documents/domain/entities/draft_save_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/review_queue_item.dart';
import 'package:legal_library_manager/features/documents/domain/entities/review_queue_query.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_list_repository.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_metadata_repository.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/review_queue_repository.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/approve_classification.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/load_document_aggregate.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/return_to_in_progress.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/save_document_draft.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/validate_classification.dart';
import 'package:legal_library_manager/features/documents/presentation/bloc/review_bloc.dart';
import 'package:legal_library_manager/features/documents/presentation/pages/document_review_page.dart';
import 'package:legal_library_manager/features/export/domain/entities/mark_ready_for_export_result.dart';
import 'package:legal_library_manager/features/export/presentation/bloc/mark_ready_for_export_bloc.dart';
import 'package:legal_library_manager/features/file_open/application/open_file_use_case.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_file_result.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_target.dart';
import 'package:legal_library_manager/features/file_open/domain/repositories/file_open_repository.dart';
import 'package:legal_library_manager/features/file_open/domain/services/file_existence_checker.dart';
import 'package:legal_library_manager/features/file_open/domain/services/os_file_opener.dart';
import 'package:legal_library_manager/features/file_open/presentation/bloc/file_open_bloc.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_error.dart';
import 'package:legal_library_manager/features/managed_copy/presentation/bloc/managed_copy_bloc.dart';
import 'package:legal_library_manager/features/reference/domain/entities/document_type_ref.dart';
import 'package:legal_library_manager/features/reference/domain/entities/main_category_ref.dart';
import 'package:legal_library_manager/features/reference/domain/entities/reference_item.dart';
import 'package:legal_library_manager/features/reference/domain/entities/sub_category_ref.dart';
import 'package:legal_library_manager/features/reference/domain/repositories/reference_repository.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

void main() {
  late FakeReviewQueueRepository queue;
  late FakeLoad load;
  late FakeSave save;
  late FakeApprove approve;
  late FakeReturn ret;
  late FakeOpenFileUseCase openFile;
  late FakeDocumentListRepo docListRepo;

  DocumentAggregate agg(
    int id, {
    String status = WorkflowStatusKey.inProgress,
    String title = 'مستند',
    DocumentClassificationInput? primary,
  }) => DocumentAggregate(
    documentId: id,
    workflowStatusKey: status,
    common: DocumentCommonMetadata(documentTypeId: 1, title: '$title $id'),
    details: null,
    primaryClassification: primary,
    additionalClassifications: const [],
    keywords: const [],
    files: const [],
    conversions: const [],
  );

  ReviewQueueItem qItem(int id, {String status = WorkflowStatusKey.imported}) =>
      ReviewQueueItem(
        id: id,
        workflowStatusKey: status,
        updatedAt: '2026-06-09T12:00:00.000Z',
        title: 'مستند $id',
        documentCode: 'DOC-000$id',
      );

  ReviewQueuePage qPage(List<ReviewQueueItem> items) => ReviewQueuePage(
    items: items,
    totalCount: items.length,
    offset: 0,
    limit: 50,
  );

  setUp(() async {
    await getIt.reset();
    queue = FakeReviewQueueRepository((q) async => qPage([qItem(1), qItem(2)]));
    load = FakeLoad()..handler = (id) async => agg(id);
    save = FakeSave();
    approve = FakeApprove();
    ret = FakeReturn();
    openFile = FakeOpenFileUseCase();
    docListRepo = FakeDocumentListRepo();
    getIt
      ..registerSingleton<ReferenceRepository>(FakeReferenceRepository())
      ..registerSingleton<CategoryManagementRepository>(
        FakeCategoryManagementRepository(),
      )
      ..registerSingleton<DocumentListRepository>(docListRepo)
      ..registerFactory<ReviewBloc>(
        () => ReviewBloc(
          queueRepository: queue,
          loadDocument: load,
          saveDraft: save,
          approveClassification: approve,
          returnToInProgress: ret,
        ),
      )
      ..registerFactory<FileOpenBloc>(() => FileOpenBloc(openFile))
      ..registerFactory<ManagedCopyBloc>(
        () => ManagedCopyBloc.executor(
          (_) async => const ManagedCopyBlocked(
            error: ManagedCopyError.notClassified,
            safeMessage: 'blocked in widget test',
          ),
        ),
      )
      ..registerFactory<MarkReadyForExportBloc>(
        () => MarkReadyForExportBloc.executor(
          (_) async => const MarkReadyForExportSuccess(),
        ),
      );
  });

  tearDown(() => getIt.reset());

  testWidgets('loads the queue and shows an empty form prompt', (tester) async {
    await _pump(tester);
    expect(find.text('مستند 1'), findsWidgets);
    expect(find.text('لم يُحدد مستند'), findsOneWidget);
  });

  testWidgets('switching scope requests the classified queue', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('المصنّفة'));
    await tester.pumpAndSettle();
    expect(
      queue.queries.any((q) => q.scope == ReviewQueueScope.classified),
      isTrue,
    );
  });

  testWidgets('both queue scope options are available', (tester) async {
    await _pump(tester);
    expect(find.text('قيد المراجعة'), findsOneWidget);
    expect(find.text('المصنّفة'), findsOneWidget);
  });

  testWidgets('scope selector uses a compact non-pill shape', (tester) async {
    await _pump(tester);

    // The Material 3 pill/stadium control is gone.
    expect(find.byType(SegmentedButton), findsNothing);

    final selector = find.byKey(const Key('review_scope_selector'));
    expect(selector, findsOneWidget);

    // No stadium/pill shape anywhere inside the selector subtree.
    expect(
      find.descendant(
        of: selector,
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.decoration is ShapeDecoration,
        ),
      ),
      findsNothing,
    );

    // Every rounded corner in the selector is at most 6px (never an oval/pill).
    final containers = tester.widgetList<Container>(
      find.descendant(of: selector, matching: find.byType(Container)),
    );
    var checkedAtLeastOneRadius = false;
    for (final container in containers) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration) {
        final radius = decoration.borderRadius;
        if (radius is BorderRadius) {
          for (final corner in [
            radius.topLeft,
            radius.topRight,
            radius.bottomLeft,
            radius.bottomRight,
          ]) {
            checkedAtLeastOneRadius = true;
            expect(corner.x, lessThanOrEqualTo(6));
            expect(corner.y, lessThanOrEqualTo(6));
          }
        }
      }
    }
    expect(checkedAtLeastOneRadius, isTrue);
  });

  testWidgets('scope selector renders without overflow across widths', (
    tester,
  ) async {
    for (final size in const [
      Size(1440, 900),
      Size(1280, 800),
      Size(1008, 720),
      Size(640, 600),
    ]) {
      await _pump(tester, size: size);
      expect(find.byKey(const Key('review_scope_selector')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }
  });

  testWidgets('selecting a document loads it into the form', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'العنوان'), findsOneWidget);
    expect(find.text('مستند 1'), findsWidgets);
    expect(find.text('source.pdf'), findsOneWidget);
  });

  testWidgets('editing marks dirty and disables approval', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'العنوان'),
      'عنوان معدّل',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('لديك تعديلات غير محفوظة'), findsOneWidget);
    final approveButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'اعتماد التصنيف'),
    );
    expect(approveButton.onPressed, isNull);
  });

  testWidgets('saving a draft reports success', (tester) async {
    save.handler = (_) async => const ValidationResult.valid();
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'العنوان'),
      'عنوان جديد',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'حفظ كمسودة'));
    await tester.pumpAndSettle();

    expect(save.callCount, 1);
    expect(find.text('تم حفظ المسودة.'), findsOneWidget);
    await _flushSnackBar(tester);
  });

  testWidgets('dirty selection change can be cancelled', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'العنوان'), 'تعديل');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('review_queue_tile_2')));
    await tester.pumpAndSettle();
    expect(find.text('تعديلات غير محفوظة'), findsOneWidget);

    await tester.tap(find.text('البقاء والتعديل'));
    await tester.pumpAndSettle();
    // Still on document 1 (its edited title is retained).
    expect(find.text('تعديل'), findsWidgets);
  });

  testWidgets('dirty selection change can be confirmed', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'العنوان'), 'تعديل');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('review_queue_tile_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تجاهل والانتقال'));
    await tester.pumpAndSettle();
    // Document 2 is now loaded.
    expect(find.text('مستند 2'), findsWidgets);
  });

  testWidgets('approval validation failure shows Arabic feedback', (
    tester,
  ) async {
    approve.handler = (_) async => ValidationResult([
      const ValidationError(
        field: 'book.author',
        code: 'required',
        message: 'required',
      ),
    ]);
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'اعتماد التصنيف'));
    await tester.pumpAndSettle();

    expect(find.textContaining('المؤلف: حقل مطلوب'), findsOneWidget);
  });

  testWidgets('approval success auto-selects the next document', (
    tester,
  ) async {
    var approved = false;
    queue = FakeReviewQueueRepository(
      (q) async => approved ? qPage([qItem(2)]) : qPage([qItem(1), qItem(2)]),
    );
    approve.handler = (_) async {
      approved = true;
      return const ValidationResult.valid();
    };
    getIt
      ..unregister<ReviewBloc>()
      ..registerFactory<ReviewBloc>(
        () => ReviewBloc(
          queueRepository: queue,
          loadDocument: load,
          saveDraft: save,
          approveClassification: approve,
          returnToInProgress: ret,
        ),
      );

    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'اعتماد التصنيف'));
    await tester.pumpAndSettle();

    expect(find.text('تم اعتماد التصنيف.'), findsOneWidget);
    // Document 2 became the active selection.
    expect(find.text('مستند 2'), findsWidgets);
    await _flushSnackBar(tester);
  });

  testWidgets('return to in_progress requires confirmation and succeeds', (
    tester,
  ) async {
    load.handler = (id) async => agg(id, status: WorkflowStatusKey.classified);
    ret.handler = (_) async => const ValidationResult.valid();
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'إعادة إلى قيد التصنيف'),
    );
    await tester.pumpAndSettle();
    expect(find.text('إعادة إلى قيد التصنيف'), findsWidgets);

    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(ret.callCount, 1);
    expect(find.text('أُعيد المستند إلى قيد التصنيف.'), findsOneWidget);
    await _flushSnackBar(tester);
  });

  testWidgets('keywords can be added as chips', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('إضافة الكلمة المفتاحية'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'أضف كلمة مفتاحية'),
      'عدالة',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إضافة الكلمة المفتاحية'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'عدالة'), findsOneWidget);
  });

  testWidgets('duplicate additional classification is prevented', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    Future<void> addPublicLaw() async {
      await tester.ensureVisible(find.byKey(const Key('review_add_main')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review_add_main')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('القانون العام').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'إضافة تصنيف'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'إضافة تصنيف'));
      await tester.pumpAndSettle();
    }

    await addPublicLaw();
    await addPublicLaw();

    expect(find.text('هذا التصنيف مُضاف بالفعل.'), findsOneWidget);
    await _flushSnackBar(tester);
  });

  testWidgets('empty queue shows a clear message', (tester) async {
    queue = FakeReviewQueueRepository((q) async => qPage(const []));
    getIt
      ..unregister<ReviewBloc>()
      ..registerFactory<ReviewBloc>(
        () => ReviewBloc(
          queueRepository: queue,
          loadDocument: load,
          saveDraft: save,
          approveClassification: approve,
          returnToInProgress: ret,
        ),
      );
    await _pump(tester);
    expect(find.text('لا توجد مستندات في هذه القائمة.'), findsOneWidget);
  });

  testWidgets('queue load failure shows a retry that recovers', (tester) async {
    var fail = true;
    queue = FakeReviewQueueRepository((q) async {
      if (fail) throw StateError('boom');
      return qPage([qItem(1)]);
    });
    getIt
      ..unregister<ReviewBloc>()
      ..registerFactory<ReviewBloc>(
        () => ReviewBloc(
          queueRepository: queue,
          loadDocument: load,
          saveDraft: save,
          approveClassification: approve,
          returnToInProgress: ret,
        ),
      );
    await _pump(tester);
    expect(find.text('تعذّر تحميل قائمة المراجعة.'), findsOneWidget);

    fail = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review_queue_tile_1')), findsOneWidget);
  });

  testWidgets('exposes safe open actions but no mutation actions', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    // Separate Open File / Open Folder actions exist on the source card.
    expect(find.byKey(const Key('open_file_button_1')), findsOneWidget);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);

    // No source-file mutation actions appear (checked as button labels so the
    // page's descriptive safety copy never produces a false match).
    expect(find.widgetWithText(TextButton, 'حذف الملف'), findsNothing);
    expect(find.widgetWithText(TextButton, 'نقل الملف'), findsNothing);
    expect(find.widgetWithText(TextButton, 'إعادة تسمية الملف'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'حذف الملف'), findsNothing);

    // Managed copy (M8) remains disabled.
    final copy = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'نسخ إلى المكتبة المدارة'),
    );
    expect(copy.onPressed, isNull);
  });

  testWidgets('tapping Open File sends the DB file id and file target', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
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
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_folder_button_1')));
    await tester.pumpAndSettle();

    expect(openFile.calls, [(fileId: 1, target: OpenTarget.folder)]);
    expect(find.text('تم فتح مجلد الملف.'), findsOneWidget);
    await _flushSnackBar(tester);
  });

  testWidgets('opening a file does not dirty the review form', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_file_button_1')));
    await tester.pumpAndSettle();

    // Opening is read-only: no unsaved-changes indicator, and no draft save or
    // workflow mutation was triggered by the open action.
    expect(find.textContaining('لديك تعديلات غير محفوظة'), findsNothing);
    expect(save.callCount, 0);
    expect(approve.callCount, 0);
    expect(ret.callCount, 0);
    await _flushSnackBar(tester);
  });

  testWidgets('a failed open shows the mapped Arabic error', (tester) async {
    openFile.result = const OpenFileFailed(
      code: FileOpenError.noAssociatedApplication,
      safeMessage: 'unused',
    );
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_file_button_1')));
    await tester.pumpAndSettle();

    expect(
      find.text('لا يوجد تطبيق مرتبط بهذا النوع من الملفات.'),
      findsOneWidget,
    );
    await _flushSnackBar(tester);
  });

  testWidgets('renders without overflow at desktop sizes', (tester) async {
    for (final size in const [
      Size(1440, 900),
      Size(1280, 800),
      Size(1920, 1080),
      Size(1008, 720),
      Size(640, 600),
    ]) {
      await _pump(tester, size: size);
      await tester.tap(find.byKey(const Key('review_queue_tile_1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }
  });

  // ---------------------------------------------------------------------------
  // Health-based Open File visibility
  // ---------------------------------------------------------------------------

  testWidgets('healthy file shows both Open File and Open Folder buttons', (
    tester,
  ) async {
    // Default health is 'healthy'; no override needed.
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_file_button_1')), findsOneWidget);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
  });

  testWidgets(
    'corrupted file hides Open File button but shows Open Folder button',
    (tester) async {
      docListRepo.sourceFileHealthKey = FileHealthKey.corrupted;
      await _pump(tester);
      await tester.tap(find.byKey(const Key('review_queue_tile_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open_file_button_1')), findsNothing);
      expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
    },
  );

  testWidgets(
    'unreadable file hides Open File button but shows Open Folder button',
    (tester) async {
      docListRepo.sourceFileHealthKey = FileHealthKey.unreadable;
      await _pump(tester);
      await tester.tap(find.byKey(const Key('review_queue_tile_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open_file_button_1')), findsNothing);
      expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
    },
  );

  testWidgets('missing health hides Open File button', (tester) async {
    docListRepo.sourceFileHealthKey = FileHealthKey.missing;
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_file_button_1')), findsNothing);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
  });

  testWidgets('unknown health hides Open File button', (tester) async {
    docListRepo.sourceFileHealthKey = 'unknown';
    await _pump(tester);
    await tester.tap(find.byKey(const Key('review_queue_tile_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_file_button_1')), findsNothing);
    expect(find.byKey(const Key('open_folder_button_1')), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // P3.4.1 mark-ready-for-export action
  // ---------------------------------------------------------------------------

  testWidgets(
    'shows the mark-ready-for-export button for a copied_to_library document',
    (tester) async {
      load.handler = (id) async => agg(id, status: WorkflowStatusKey.copiedToLibrary);
      await _pump(tester);
      await tester.tap(find.byKey(const Key('review_queue_tile_1')));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OutlinedButton, 'تعيين جاهز للتصدير'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hides the mark-ready-for-export button for a ready_for_export document',
    (tester) async {
      load.handler = (id) async => agg(id, status: WorkflowStatusKey.readyForExport);
      await _pump(tester);
      await tester.tap(find.byKey(const Key('review_queue_tile_1')));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OutlinedButton, 'تعيين جاهز للتصدير'),
        findsNothing,
      );
      expect(find.text('جاهز للتصدير ✓'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'نسخ إلى المكتبة المدارة'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'disables the mark-ready-for-export button while ReviewBloc is busy',
    (tester) async {
      load.handler = (id) async => agg(id, status: WorkflowStatusKey.copiedToLibrary);
      save.handler = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const ValidationResult.valid();
      };
      await _pump(tester);
      await tester.tap(find.byKey(const Key('review_queue_tile_1')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'حفظ كمسودة'));
      await tester.pump();

      final exportButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'تعيين جاهز للتصدير'),
      );
      expect(exportButton.onPressed, isNull);

      await tester.pumpAndSettle();
      await _flushSnackBar(tester);
    },
  );
}

/// Advances past the SnackBar auto-dismiss timer so no timer outlives the test.
Future<void> _flushSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
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
        child: Scaffold(body: DocumentReviewPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// --- safe-open test doubles -----------------------------------------------

class _DummyFileOpenRepo implements FileOpenRepository {
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
        repository: _DummyFileOpenRepo(),
        existenceChecker: _DummyChecker(),
        osOpener: _DummyOpener(),
      );

  final List<({int fileId, OpenTarget target})> calls = [];
  OpenFileResult result = const OpenFileSuccess(target: OpenTarget.file);

  @override
  Future<OpenFileResult> execute(int fileId, OpenTarget target) async {
    calls.add((fileId: fileId, target: target));
    return switch (result) {
      OpenFileSuccess() => OpenFileSuccess(target: target),
      OpenFileAuditFailure() => OpenFileAuditFailure(target: target),
      _ => result,
    };
  }
}

// --- test doubles ---------------------------------------------------------

class _ZeroClock extends Clock {
  const _ZeroClock();
  @override
  DateTime nowUtc() => DateTime.utc(2026);
}

class _Never implements DocumentMetadataRepository, ReferenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('repository should not be called in this test');
}

class FakeReviewQueueRepository implements ReviewQueueRepository {
  FakeReviewQueueRepository(this.handler);

  final Future<ReviewQueuePage> Function(ReviewQueueQuery query) handler;
  final List<ReviewQueueQuery> queries = [];

  @override
  Future<ReviewQueuePage> getQueue(ReviewQueueQuery query) {
    queries.add(query);
    return handler(query);
  }
}

class FakeLoad extends LoadDocumentAggregate {
  FakeLoad() : super(_Never());

  Future<DocumentAggregate?> Function(int id) handler = (_) async => null;

  @override
  Future<DocumentAggregate?> call(int documentId) => handler(documentId);
}

class FakeSave extends SaveDocumentDraft {
  FakeSave()
    : super(
        repository: _Never(),
        references: _Never(),
        classificationValidator: ValidateClassification(
          references: _Never(),
          clock: const _ZeroClock(),
        ),
        clock: const _ZeroClock(),
      );

  Future<ValidationResult> Function(DraftSaveInput input) handler = (_) async =>
      const ValidationResult.valid();
  int callCount = 0;

  @override
  Future<ValidationResult> call(DraftSaveInput input) {
    callCount++;
    return handler(input);
  }
}

class FakeApprove extends ApproveClassification {
  FakeApprove()
    : super(
        repository: _Never(),
        validator: ValidateClassification(
          references: _Never(),
          clock: const _ZeroClock(),
        ),
        clock: const _ZeroClock(),
      );

  Future<ValidationResult> Function(int id) handler = (_) async =>
      const ValidationResult.valid();
  int callCount = 0;

  @override
  Future<ValidationResult> call(int documentId) {
    callCount++;
    return handler(documentId);
  }
}

class FakeReturn extends ReturnToInProgress {
  FakeReturn() : super(repository: _Never(), clock: const _ZeroClock());

  Future<ValidationResult> Function(int id) handler = (_) async =>
      const ValidationResult.valid();
  int callCount = 0;

  @override
  Future<ValidationResult> call(int documentId) {
    callCount++;
    return handler(documentId);
  }
}

class FakeDocumentListRepo implements DocumentListRepository {
  /// Override per-test to exercise non-healthy health visibility.
  String sourceFileHealthKey = FileHealthKey.healthy;

  @override
  Future<DocumentListPage> getDocuments(DocumentListQuery query) async =>
      const DocumentListPage(items: [], totalCount: 0, offset: 0, limit: 50);

  @override
  Future<List<DocumentSourceFileItem>> getSourceFiles(int documentId) async => [
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

  @override
  Future<void> setPreferredSourceFile(int documentId, int fileId) async {}
}

class FakeReferenceRepository implements ReferenceRepository {
  static const _generic = [
    ReferenceItem(key: 'ar', nameAr: 'العربية', nameEn: 'Arabic', sortOrder: 1),
  ];

  @override
  Future<List<DocumentTypeRef>> getDocumentTypes() async => const [
    DocumentTypeRef(
      id: 1,
      key: 'book',
      nameAr: 'كتاب',
      nameEn: 'Book',
      sortOrder: 1,
    ),
    DocumentTypeRef(
      id: 2,
      key: 'thesis',
      nameAr: 'رسالة علمية',
      nameEn: 'Thesis',
      sortOrder: 2,
    ),
  ];

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
  Future<List<SubCategoryRef>> getSubCategories({
    int? mainCategoryId,
    String? mainCategoryKey,
  }) async => const [
    SubCategoryRef(
      id: 10,
      mainCategoryId: 1,
      key: 'constitutional_law',
      nameAr: 'القانون الدستوري',
      nameEn: 'Constitutional Law',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getLanguages() async => _generic;

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
  Future<ReferenceItem?> getCountryByKey(String key) async => null;

  @override
  Future<List<ReferenceItem>> getTrustLevels() async => const [
    ReferenceItem(
      key: TrustLevelKey.trusted,
      nameAr: 'موثوق',
      nameEn: 'Trusted',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getUsageRights() async => const [
    ReferenceItem(
      key: UsageRightsKey.openAccess,
      nameAr: 'وصول مفتوح',
      nameEn: 'Open Access',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getMetadataQualities() async => const [
    ReferenceItem(
      key: MetadataQualityKey.high,
      nameAr: 'عالية',
      nameEn: 'High',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getWorkflowStatuses() async => const [
    ReferenceItem(
      key: WorkflowStatusKey.inProgress,
      nameAr: 'قيد التصنيف',
      nameEn: 'In Progress',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<ReferenceItem>> getFileRoles() async => const [];

  @override
  Future<List<ReferenceItem>> getFileHealthStatuses() async => const [];
}

class FakeCategoryManagementRepository implements CategoryManagementRepository {
  @override
  Future<List<ManagedMainCategory>> getMainCategories() async => const [
    ManagedMainCategory(
      id: 1,
      key: 'public_law',
      nameAr: 'القانون العام',
      nameEn: 'Public Law',
      sortOrder: 1,
      isActive: true,
    ),
  ];

  @override
  Future<List<ManagedSubCategory>> getSubCategories({
    int? mainCategoryId,
  }) async => const [
    ManagedSubCategory(
      id: 10,
      mainCategoryId: 1,
      key: 'constitutional_law',
      nameAr: 'القانون الدستوري',
      nameEn: 'Constitutional Law',
      sortOrder: 1,
      isActive: true,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('mutation should not be called in this test');
}
