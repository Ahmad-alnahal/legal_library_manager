// test/features/export/presentation/pages/export_page_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/documents/domain/repositories/document_metadata_repository.dart';
import 'package:legal_library_manager/features/export/domain/entities/exportable_document_ref.dart';
import 'package:legal_library_manager/features/export/domain/entities/generate_export_batch_result.dart';
import 'package:legal_library_manager/features/export/domain/repositories/export_batch_repository.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_batch_summary.dart';
import 'package:legal_library_manager/features/export/presentation/bloc/export_batch_bloc.dart';
import 'package:legal_library_manager/features/export/presentation/pages/export_page.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/l10n/app_localizations.dart';

class _FakeManagedCopyRepository implements ManagedCopyRepository {
  @override
  Future<String?> loadExportRoot() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used');
}

class _FakeMetadataRepository implements DocumentMetadataRepository {
  _FakeMetadataRepository(this.readyDocs);
  final List<ExportableDocumentRef> readyDocs;

  @override
  Future<List<ExportableDocumentRef>> listReadyForExport() async => readyDocs;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used');
}

class _FakeBatchRepository implements ExportBatchRepository {
  @override
  Future<List<ExportBatchSummary>> listBatches() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used');
}

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  Future<void> pumpExport(
    WidgetTester tester, {
    required List<ExportableDocumentRef> readyDocs,
    Future<GenerateExportBatchResult> Function()? generate,
  }) async {
    getIt.registerFactory<ExportBatchBloc>(
      () => ExportBatchBloc.executor(
        managedCopyRepository: _FakeManagedCopyRepository(),
        metadataRepository: _FakeMetadataRepository(readyDocs),
        batchRepository: _FakeBatchRepository(),
        generate:
            generate ?? () async => const GenerateExportBatchNothingToExport(),
      ),
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
          child: Scaffold(body: ExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('generate button is disabled when readyForExportCount is 0', (
    tester,
  ) async {
    await pumpExport(tester, readyDocs: const []);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إنشاء حزمة تصدير'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.textContaining('لا توجد مستندات جاهزة للتصدير حالياً'),
      findsOneWidget,
    );
  });

  testWidgets(
    'generate button is enabled and shows success message after generation',
    (tester) async {
      final ref = ExportableDocumentRef(
        id: 1,
        documentCode: 'DOC-0001',
        readyForExportAt: DateTime.utc(2026, 6, 1),
      );
      await pumpExport(
        tester,
        readyDocs: [ref],
        generate: () async => const GenerateExportBatchSuccess(
          batchCode: 'EXP-2026-06-01-001',
          exportPath: r'D:\Exports\batch',
          includedCount: 1,
          skippedCount: 0,
          skippedReasons: [],
          flaggedUsageRights: [],
        ),
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'إنشاء حزمة تصدير'),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'إنشاء حزمة تصدير'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('تم إنشاء الحزمة بنجاح: EXP-2026-06-01-001'),
        findsOneWidget,
      );
    },
  );
}
