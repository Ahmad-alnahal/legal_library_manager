import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_document_metadata_repository.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_classification_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_common_metadata.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_type_details.dart';
import 'package:legal_library_manager/features/documents/domain/entities/draft_save_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/keyword_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/normalized_draft.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/save_document_draft.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/validate_classification.dart';
import 'package:legal_library_manager/features/reference/data/repositories/drift_reference_repository.dart';

import 'support/document_test_support.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentMetadataRepository metaRepo;
  late SaveDocumentDraft saveDraft;
  final clock = FixedClock(DateTime.utc(2026, 6, 7));

  group('SaveDocumentDraft', () {
    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      metaRepo = DriftDocumentMetadataRepository(db);
      final refRepo = DriftReferenceRepository(db);
      saveDraft = SaveDocumentDraft(
        repository: metaRepo,
        references: refRepo,
        classificationValidator: ValidateClassification(
          references: refRepo,
          clock: clock,
        ),
        clock: clock,
      );
    });

    tearDown(() async => db.close());

    test('incomplete valid draft saves and sets in_progress', () async {
      final int docId = await insertDocument(db);
      final int bookType = await typeId(db, 'book');
      final int publicLaw = await mainId(db, 'public_law');

      final result = await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: DocumentCommonMetadata(
            documentTypeId: bookType,
            title: 'كتاب القانون',
            languageKey: 'ar',
          ),
          primaryClassification: DocumentClassificationInput(
            mainCategoryId: publicLaw,
          ),
          keywords: const [KeywordInput(displayValue: 'عقد')],
        ),
      );

      expect(result.isValid, isTrue);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.workflowStatusKey, 'in_progress');
      expect(doc.updatedAt, '2026-06-07T00:00:00.000Z');
      expect(doc.documentCode, isNull);
    });

    test('rejects invalid entered fields without writing', () async {
      final int docId = await insertDocument(db);
      final result = await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: DocumentCommonMetadata(title: 'x' * 501),
        ),
      );
      expect(result.isInvalid, isTrue);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      // Untouched: still the imported default, title still null.
      expect(doc.workflowStatusKey, 'imported');
      expect(doc.title, isNull);
    });

    test(
      'repository rolls back all changes on a mid-transaction failure',
      () async {
        final int docId = await insertDocument(db);
        // Bypass the use case to feed a draft that passes nothing but the DB:
        // an additional classification referencing a non-existent main category
        // makes the classification insert fail after the documents update.
        final bad = NormalizedDraft(
          documentId: docId,
          common: const DocumentCommonMetadata(title: 'should not persist'),
          details: null,
          primaryClassification: null,
          additionalClassifications: const [
            DocumentClassificationInput(mainCategoryId: 999999),
          ],
          keywords: const [],
        );

        await expectLater(
          metaRepo.saveDraft(
            bad,
            now: DateTime.utc(2026, 6, 7),
            workflowStatusKey: 'in_progress',
            clearClassifiedAt: true,
          ),
          throwsA(anything),
        );

        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();
        expect(doc.title, isNull, reason: 'documents update must roll back');
        expect(doc.workflowStatusKey, 'imported');
        expect(await db.select(db.documentClassifications).get(), isEmpty);
      },
    );

    test(
      'primary classification and denormalized fields stay in sync',
      () async {
        final int docId = await insertDocument(db);
        final int publicLaw = await mainId(db, 'public_law');
        final int constitutional = await subId(db, 'constitutional_law');

        await saveDraft.call(
          DraftSaveInput(
            documentId: docId,
            common: const DocumentCommonMetadata(),
            primaryClassification: DocumentClassificationInput(
              mainCategoryId: publicLaw,
              subCategoryId: constitutional,
            ),
          ),
        );

        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();
        expect(doc.primaryMainCategoryId, publicLaw);
        expect(doc.primarySubCategoryId, constitutional);

        final primaryRows =
            await (db.select(db.documentClassifications)..where(
                  (c) =>
                      c.documentId.equals(docId) &
                      c.classificationRoleKey.equals('primary'),
                ))
                .get();
        expect(primaryRows.length, 1);
        expect(primaryRows.single.mainCategoryId, publicLaw);
        expect(primaryRows.single.subCategoryId, constitutional);
      },
    );

    test('changing document type removes obsolete detail rows', () async {
      final int docId = await insertDocument(db);
      final int bookType = await typeId(db, 'book');
      final int thesisType = await typeId(db, 'thesis');

      await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: DocumentCommonMetadata(documentTypeId: bookType),
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      expect((await db.select(db.bookDetails).get()).length, 1);

      await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: DocumentCommonMetadata(documentTypeId: thesisType),
          details: const ThesisDetailsData(researcherName: 'باحث'),
        ),
      );
      expect((await db.select(db.bookDetails).get()), isEmpty);
      expect((await db.select(db.thesisDetails).get()).length, 1);
    });

    test('keywords normalize, reuse rows, and never duplicate links', () async {
      final int docId = await insertDocument(db);
      await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: const DocumentCommonMetadata(),
          keywords: const [
            KeywordInput(displayValue: 'Qanun'),
            KeywordInput(displayValue: '  qanun  '),
          ],
        ),
      );
      // Two inputs normalize to one keyword and one link.
      expect((await db.select(db.keywords).get()).length, 1);
      expect((await db.select(db.documentKeywords).get()).length, 1);

      // A second document reuses the same keyword row.
      final int doc2 = await insertDocument(db);
      await saveDraft.call(
        DraftSaveInput(
          documentId: doc2,
          common: const DocumentCommonMetadata(),
          keywords: const [KeywordInput(displayValue: 'QANUN')],
        ),
      );
      expect((await db.select(db.keywords).get()).length, 1);
      expect((await db.select(db.documentKeywords).get()).length, 2);
    });

    test('additional classifications are replaced on re-save', () async {
      final int docId = await insertDocument(db);
      final int publicLaw = await mainId(db, 'public_law');
      final int privateLaw = await mainId(db, 'private_law');
      final int intlLaw = await mainId(db, 'international_law');

      await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: const DocumentCommonMetadata(),
          additionalClassifications: [
            DocumentClassificationInput(mainCategoryId: publicLaw),
            DocumentClassificationInput(mainCategoryId: privateLaw),
          ],
        ),
      );
      expect((await db.select(db.documentClassifications).get()).length, 2);

      await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: const DocumentCommonMetadata(),
          additionalClassifications: [
            DocumentClassificationInput(mainCategoryId: intlLaw),
          ],
        ),
      );
      final rows = await db.select(db.documentClassifications).get();
      expect(rows.length, 1);
      expect(rows.single.mainCategoryId, intlLaw);
    });

    test('does not create document files', () async {
      final int docId = await insertDocument(db);
      await saveDraft.call(
        DraftSaveInput(
          documentId: docId,
          common: const DocumentCommonMetadata(title: 'عنوان'),
        ),
      );
      expect(await db.select(db.documentFiles).get(), isEmpty);
    });

    // --- classified-document editing (workflow spec §5) ---

    /// Builds a fully-approvable book draft for [docId] with the given author.
    Future<DraftSaveInput> approvableBookDraft(
      int docId, {
      String? author = 'مؤلف',
      String title = 'عنوان',
    }) async => DraftSaveInput(
      documentId: docId,
      common: DocumentCommonMetadata(
        documentTypeId: await typeId(db, 'book'),
        title: title,
        languageKey: 'ar',
        trustLevelKey: 'trusted',
        usageRightsKey: 'open_access',
        metadataQualityKey: 'high',
      ),
      primaryClassification: DocumentClassificationInput(
        mainCategoryId: await mainId(db, 'public_law'),
        subCategoryId: await subId(db, 'constitutional_law'),
      ),
      details: BookDetailsData(author: author),
    );

    /// Saves an approvable book then forces it to a classified state, as a
    /// prior approval would have.
    Future<int> classifiedBook() async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(await approvableBookDraft(id));
      await (db.update(db.documents)..where((d) => d.id.equals(id))).write(
        const DocumentsCompanion(
          workflowStatusKey: Value('classified'),
          classifiedAt: Value('2026-01-01T00:00:00.000Z'),
        ),
      );
      return id;
    }

    test('ordinary draft save never auto-promotes to classified', () async {
      final int docId = await insertDocument(db);
      await addHealthySource(db, docId);
      // Even a fully approvable draft stays in_progress on a plain save.
      final r = await saveDraft.call(await approvableBookDraft(docId));
      expect(r.isValid, isTrue);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.workflowStatusKey, 'in_progress');
      expect(doc.classifiedAt, isNull);
    });

    test('valid edit of a classified document stays classified', () async {
      final int id = await classifiedBook();
      final r = await saveDraft.call(
        await approvableBookDraft(id, title: 'عنوان محدث'),
      );
      expect(r.isValid, isTrue);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(doc.workflowStatusKey, 'classified');
      // classified_at preserved; only updated_at advances.
      expect(doc.classifiedAt, '2026-01-01T00:00:00.000Z');
      expect(doc.title, 'عنوان محدث');
      expect(doc.updatedAt, '2026-06-07T00:00:00.000Z');
    });

    test(
      'invalidating edit of a classified document returns to in_progress',
      () async {
        final int id = await classifiedBook();
        // Removing the required author makes the prospective aggregate fail
        // approval.
        final r = await saveDraft.call(
          await approvableBookDraft(id, author: null),
        );
        expect(r.isValid, isTrue, reason: 'draft itself is still well-formed');
        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(id))).getSingle();
        expect(doc.workflowStatusKey, 'in_progress');
        expect(doc.classifiedAt, isNull);
      },
    );
  });
}
