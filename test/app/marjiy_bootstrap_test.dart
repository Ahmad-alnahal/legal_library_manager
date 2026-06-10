import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/app/marjiy_bootstrap.dart';

void main() {
  const readyKey = Key('ready_home');

  testWidgets('shows progress while startup is still running', (tester) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      MarjiyBootstrap(
        initializer: () => completer.future,
        errorReporter: (_, _) {},
        readyHome: const SizedBox(key: readyKey),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('جارٍ تجهيز مرجعي...'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(readyKey), findsOneWidget);
  });

  testWidgets('shows a safe failure screen and retries startup', (
    tester,
  ) async {
    int attempts = 0;

    await tester.pumpWidget(
      MarjiyBootstrap(
        initializer: () async {
          attempts++;
          if (attempts == 1) throw StateError('private startup detail');
        },
        errorReporter: (_, _) {},
        readyHome: const SizedBox(key: readyKey),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعذّر تجهيز قاعدة البيانات المحلية'), findsOneWidget);
    expect(find.textContaining('لم يتم نقل أي ملف أصلي'), findsOneWidget);
    expect(find.textContaining('private startup detail'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byKey(readyKey), findsOneWidget);
  });
}
