import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_document_metadata_repository.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_classification_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_common_metadata.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_type_details.dart';
import 'package:legal_library_manager/features/documents/domain/entities/draft_save_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/keyword_input.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/approve_classification.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/load_document_aggregate.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/return_to_in_progress.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/save_document_draft.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/validate_classification.dart';
import 'package:legal_library_manager/features/reference/data/repositories/drift_reference_repository.dart';

import 'support/document_test_support.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentMetadataRepository metaRepo;
  late SaveDocumentDraft saveDraft;
  late ApproveClassification approve;
  late LoadDocumentAggregate loadAggregate;
  late ReturnToInProgress returnToInProgress;
  final clock = FixedClock(DateTime.utc(2026, 6, 9));

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    metaRepo = DriftDocumentMetadataRepository(db);
    final refRepo = DriftReferenceRepository(db);
    final validator = ValidateClassification(references: refRepo, clock: clock);
    saveDraft = SaveDocumentDraft(
      repository: metaRepo,
      references: refRepo,
      classificationValidator: validator,
      clock: clock,
    );
    approve = ApproveClassification(
      repository: metaRepo,
      validator: validator,
      clock: clock,
    );
    loadAggregate = LoadDocumentAggregate(metaRepo);
    returnToInProgress = ReturnToInProgress(repository: metaRepo, clock: clock);
  });

  tearDown(() async => db.close());

  Future<DocumentCommonMetadata> validBookCommon() async =>
      DocumentCommonMetadata(
        documentTypeId: await typeId(db, 'book'),
        title: 'عنوان',
        languageKey: 'ar',
        trustLevelKey: 'trusted',
        usageRightsKey: 'open_access',
        metadataQualityKey: 'high',
      );

  Future<DocumentClassificationInput> publicLawConstitutional() async =>
      DocumentClassificationInput(
        mainCategoryId: await mainId(db, 'public_law'),
        subCategoryId: await subId(db, 'constitutional_law'),
      );

  Future<int> classifiedBook() async {
    final int id = await insertDocument(db);
    await addHealthySource(db, id);
    await saveDraft.call(
      DraftSaveInput(
        documentId: id,
        common: await validBookCommon(),
        primaryClassification: await publicLawConstitutional(),
        details: const BookDetailsData(author: 'مؤلف'),
        keywords: const [KeywordInput(displayValue: 'عدالة')],
      ),
    );
    final r = await approve.call(id);
    expect(r.isValid, isTrue);
    return id;
  }

  group('LoadDocumentAggregate', () {
    test('loads the complete aggregate', () async {
      final int id = await classifiedBook();

      final agg = await loadAggregate.call(id);

      expect(agg, isNotNull);
      expect(agg!.documentId, id);
      expect(agg.workflowStatusKey, 'classified');
      expect(agg.common.title, 'عنوان');
      expect(agg.common.languageKey, 'ar');
      expect(agg.details, isA<BookDetailsData>());
      expect((agg.details! as BookDetailsData).author, 'مؤلف');
      expect(agg.primaryClassification, isNotNull);
      expect(agg.keywords.map((k) => k.displayValue), contains('عدالة'));
      expect(agg.files, isNotEmpty);
      expect(agg.classifiedAt, isNotNull);
    });

    test('returns null for a missing document', () async {
      expect(await loadAggregate.call(999999), isNull);
    });
  });

  group('ReturnToInProgress', () {
    test('returns a classified document to in_progress', () async {
      final int id = await classifiedBook();
      final int filesBefore = (await db.select(db.documentFiles).get()).length;

      final result = await returnToInProgress.call(id);
      expect(result.isValid, isTrue);

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(doc.workflowStatusKey, 'in_progress');
      expect(doc.classifiedAt, isNull);
      expect(doc.updatedAt, '2026-06-09T00:00:00.000Z');
      // No managed copy / file mutation: file rows are unchanged.
      expect((await db.select(db.documentFiles).get()).length, filesBefore);
      expect(await db.select(db.fileEvents).get(), isEmpty);
    });

    test('rejects a document that is not classified', () async {
      final int id = await insertDocument(db); // imported
      final result = await returnToInProgress.call(id);
      expect(result.isInvalid, isTrue);
      expect(result.hasCode('invalid_status'), isTrue);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(doc.workflowStatusKey, 'imported');
    });

    test('returns not_found for a missing document', () async {
      final result = await returnToInProgress.call(999999);
      expect(result.hasCode('not_found'), isTrue);
    });
  });
}
