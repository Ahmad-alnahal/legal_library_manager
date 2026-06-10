import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/categories/presentation/pages/category_management_page.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AppDatabase>(
      AppDatabase.inMemory(),
      dispose: (db) => db.close(),
    );
    configureDependencies();
  });

  tearDown(() => getIt.reset());

  testWidgets('loads the standalone category-management workspace', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('إدارة التصنيفات'), findsOneWidget);
    expect(find.byKey(const Key('category_add_main')), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.delete_forever_outlined), findsNothing);
  });

  testWidgets('adds a main category through the management page', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('category_add_main')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_ar')),
      'فئة جديدة',
    );
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_en')),
      'New Category',
    );
    await tester.tap(find.byKey(const Key('category_dialog_submit')));
    await tester.pumpAndSettle();

    expect(find.text('فئة جديدة'), findsOneWidget);
    expect(find.text('New Category'), findsOneWidget);
  });

  testWidgets('keeps the dialog open with an inline invalid-character error', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('category_add_main')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_ar')),
      'فئة${String.fromCharCode(0x200B)}',
    );
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_en')),
      'Valid Name',
    );
    await tester.tap(find.byKey(const Key('category_dialog_submit')));
    await tester.pumpAndSettle();

    // Dialog stays open (the fields are still present, with values preserved).
    expect(find.byKey(const Key('category_dialog_name_ar')), findsOneWidget);
    expect(find.text('Valid Name'), findsOneWidget);
    expect(
      find.text(
        'يحتوي الاسم العربي على رموز تحكم أو محارف غير مرئية غير مسموح بها.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows an inline script error and preserves entered values', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('category_add_main')));
    await tester.pumpAndSettle();
    // Latin text typed into the Arabic field, Arabic text into the English one.
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_ar')),
      'Public Law',
    );
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_en')),
      'القانون العام',
    );
    await tester.tap(find.byKey(const Key('category_dialog_submit')));
    await tester.pumpAndSettle();

    // Dialog stays open, values preserved, and both Arabic messages are shown.
    expect(find.byKey(const Key('category_dialog_name_ar')), findsOneWidget);
    expect(find.text('Public Law'), findsOneWidget);
    expect(find.text('القانون العام'), findsOneWidget);
    expect(
      find.text(
        'يجب أن يحتوي الاسم العربي على حروف عربية فقط دون حروف لاتينية.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'يجب أن يحتوي الاسم الإنجليزي على حروف لاتينية فقط دون حروف عربية.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows an inline duplicate error and preserves entered values', (
    tester,
  ) async {
    await _pump(tester);

    // Add a first category.
    await tester.tap(find.byKey(const Key('category_add_main')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_ar')),
      'فئة مكررة',
    );
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_en')),
      'Duplicate Cat',
    );
    await tester.tap(find.byKey(const Key('category_dialog_submit')));
    await tester.pumpAndSettle();

    // Try to add the same Arabic name again.
    await tester.tap(find.byKey(const Key('category_add_main')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_ar')),
      'فئة مكررة',
    );
    await tester.enterText(
      find.byKey(const Key('category_dialog_name_en')),
      'Another English',
    );
    await tester.tap(find.byKey(const Key('category_dialog_submit')));
    await tester.pumpAndSettle();

    // Dialog stays open with the friendly Arabic duplicate message and the
    // entered English value preserved.
    expect(find.byKey(const Key('category_dialog_name_ar')), findsOneWidget);
    expect(find.text('Another English'), findsOneWidget);
    expect(find.text('يوجد بالفعل تصنيف بنفس الاسم العربي.'), findsOneWidget);
  });

  testWidgets('add-category dialog has no sort-order field', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('category_add_main')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('category_dialog_sort')), findsNothing);
    // The two name fields are present and nothing else numeric.
    expect(find.byKey(const Key('category_dialog_name_ar')), findsOneWidget);
    expect(find.byKey(const Key('category_dialog_name_en')), findsOneWidget);
  });

  testWidgets('reorder buttons appear after adding two main categories', (
    tester,
  ) async {
    await _pump(tester);

    Future<void> addMain(String ar, String en) async {
      await tester.tap(find.byKey(const Key('category_add_main')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category_dialog_name_ar')),
        ar,
      );
      await tester.enterText(
        find.byKey(const Key('category_dialog_name_en')),
        en,
      );
      await tester.tap(find.byKey(const Key('category_dialog_submit')));
      await tester.pumpAndSettle();
    }

    await addMain('فئة أولى', 'Category One');
    await addMain('فئة ثانية', 'Category Two');

    // At least one move-up and one move-down button must exist now.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.key != null &&
            w.key.toString().contains('category_main_move_up_'),
      ),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.key != null &&
            w.key.toString().contains('category_main_move_down_'),
      ),
      findsWidgets,
    );
  });

  testWidgets('first displayed item has move-up button disabled', (
    tester,
  ) async {
    await _pump(tester);

    Future<void> addMain(String ar, String en) async {
      await tester.tap(find.byKey(const Key('category_add_main')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category_dialog_name_ar')),
        ar,
      );
      await tester.enterText(
        find.byKey(const Key('category_dialog_name_en')),
        en,
      );
      await tester.tap(find.byKey(const Key('category_dialog_submit')));
      await tester.pumpAndSettle();
    }

    await addMain('فئة أ', 'Cat A');
    await addMain('فئة ب', 'Cat B');

    // Find all move-up buttons and assert that exactly one is disabled
    // (the first item in the list).
    final moveUpButtons = tester.widgetList<IconButton>(
      find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.key != null &&
            w.key.toString().contains('category_main_move_up_'),
      ),
    );
    final disabledCount = moveUpButtons
        .where((b) => b.onPressed == null)
        .length;
    expect(
      disabledCount,
      1,
      reason: 'only the first item must have move-up disabled',
    );
  });

  for (final size in [
    const Size(1440, 900),
    const Size(1008, 720),
    const Size(640, 600),
  ]) {
    testWidgets('renders without overflow at $size', (tester) async {
      await _pump(tester, size: size);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
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
        child: Scaffold(body: CategoryManagementPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
