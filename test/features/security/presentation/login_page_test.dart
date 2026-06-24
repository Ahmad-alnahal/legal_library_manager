import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/app/app.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/security/presentation/pages/login_page.dart';

import '../../../support/managed_copy_test_doubles.dart';
import '../../../support/security_test_doubles.dart';

Future<void> _pumpLoginPage(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const MarjiyApp(home: LoginPage()),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AppDatabase>(
      AppDatabase.inMemory(),
      dispose: (db) => db.close(),
    );
    configureDependencies();
    useStubDocumentsDirectoryResolver();
    // Unauth session — login page is shown on its own, not via AuthGatePage.
    useStubSessionManager(session: null);
  });

  testWidgets('LoginPage has username and password fields in RTL', (
    tester,
  ) async {
    await _pumpLoginPage(tester);
    // Both fields must exist.
    expect(find.byType(TextField), findsAtLeastNWidgets(2));
    // Page is RTL.
    final context = tester.element(find.byType(LoginPage));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('LoginPage has a login submit button', (tester) async {
    await _pumpLoginPage(tester);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  // Loading-indicator transient state is verified at the BLoC unit level
  // (login_bloc_test.dart emits LoginInProgress before LoginInvalidCredentials).
  // In widget tests the in-memory DB query resolves within the same microtask
  // batch, so the CircularProgressIndicator is never observable in a pump().

  testWidgets('LoginPage shows error on wrong credentials after settle', (
    tester,
  ) async {
    await _pumpLoginPage(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'marjiy@admin');
    await tester.enterText(fields.last, 'WrongPassword');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // An error banner must appear (contains Arabic warning text).
    expect(
      find.textContaining('غير صحيحة'),
      findsOneWidget,
    );
  });

  testWidgets('password field has show/hide toggle', (tester) async {
    await _pumpLoginPage(tester);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
