import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/app/marjiy_bootstrap.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/inspect_startup_recovery.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';

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

  testWidgets('startup loading screen shows app title and logo mark', (
    tester,
  ) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      MarjiyBootstrap(
        initializer: () => completer.future,
        errorReporter: (_, _) {},
        readyHome: const SizedBox(key: readyKey),
      ),
    );

    // Brand identity is visible while loading.
    expect(find.text('مرجعي'), findsOneWidget);
    // Logo mark asset rendered as Image.asset.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/logo_mark.png',
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    // The ready home replaces the loading view entirely.
    expect(find.byKey(readyKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
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

  test('initializeApplication runs startup recovery inspection', () async {
    await getIt.reset();
    final calls = <String>[];
    getIt.registerSingleton<AppDatabase>(
      AppDatabase.inMemory(),
      dispose: (db) => db.close(),
    );
    configureDependencies();
    await getIt.unregister<InitializeCopyRoots>();
    await getIt.unregister<InspectStartupRecovery>();
    getIt.registerSingleton<InitializeCopyRoots>(
      _FakeInitializeCopyRoots(calls),
    );
    getIt.registerSingleton<InspectStartupRecovery>(
      _FakeInspectStartupRecovery(calls),
    );
    addTearDown(getIt.reset);

    await initializeApplication();

    expect(calls, ['initialize_roots', 'inspect_startup_recovery']);
  });
}

class _FakeInitializeCopyRoots implements InitializeCopyRoots {
  _FakeInitializeCopyRoots(this.calls);

  final List<String> calls;

  @override
  Future<CopyRootsSetupReport> call() async {
    calls.add('initialize_roots');
    return const CopyRootsSetupReport(
      outcome: CopyRootsSetupOutcome.alreadyConfigured,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInspectStartupRecovery implements InspectStartupRecovery {
  _FakeInspectStartupRecovery(this.calls);

  final List<String> calls;

  @override
  Future<StartupRecoveryReport> call() async {
    calls.add('inspect_startup_recovery');
    return StartupRecoveryReport.healthy;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
