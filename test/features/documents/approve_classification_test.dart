import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_document_metadata_repository.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_classification_input.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_common_metadata.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_type_details.dart';
import 'package:legal_library_manager/features/documents/domain/entities/draft_save_input.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/approve_classification.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/save_document_draft.dart';
import 'package:legal_library_manager/features/documents/domain/usecases/validate_classification.dart';
import 'package:legal_library_manager/features/reference/data/repositories/drift_reference_repository.dart';

import 'support/document_test_support.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentMetadataRepository metaRepo;
  late SaveDocumentDraft saveDraft;
  late ApproveClassification approve;
  final clock = FixedClock(DateTime.utc(2026, 6, 7));

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
  });

  tearDown(() async => db.close());

  // Common metadata that satisfies all non-type-specific approval fields.
  Future<DocumentCommonMetadata> validCommon(String typeKey) async =>
      DocumentCommonMetadata(
        documentTypeId: await typeId(db, typeKey),
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

  Future<String> statusOf(int id) async => (await (db.select(
    db.documents,
  )..where((d) => d.id.equals(id))).getSingle()).workflowStatusKey;

  group('ApproveClassification — type-specific rules', () {
    test('book: approves with author, fails without', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      final common = await validCommon('book');
      final primary = await publicLawConstitutional();

      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: common,
          primaryClassification: primary,
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      expect((await approve.call(id)).isValid, isTrue);
      expect(await statusOf(id), 'classified');

      // Without author.
      final int id2 = await insertDocument(db);
      await addHealthySource(db, id2);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id2,
          common: await validCommon('book'),
          primaryClassification: await publicLawConstitutional(),
          details: const BookDetailsData(),
        ),
      );
      final r = await approve.call(id2);
      expect(r.isInvalid, isTrue);
      expect(r.hasError('book.author'), isTrue);
      expect(await statusOf(id2), 'in_progress');
    });

    test('thesis: requires researcher, degree, university', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('thesis'),
          primaryClassification: await publicLawConstitutional(),
          details: const ThesisDetailsData(
            researcherName: 'باحث',
            degreeTypeKey: 'masters',
            universityName: 'جامعة',
          ),
        ),
      );
      expect((await approve.call(id)).isValid, isTrue);

      final int id2 = await insertDocument(db);
      await addHealthySource(db, id2);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id2,
          common: await validCommon('thesis'),
          primaryClassification: await publicLawConstitutional(),
          details: const ThesisDetailsData(
            researcherName: 'باحث',
            degreeTypeKey: 'masters',
          ),
        ),
      );
      expect(
        (await approve.call(id2)).hasError('thesis.universityName'),
        isTrue,
      );
    });

    test('research: researcher OR publishing entity', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('research_paper'),
          primaryClassification: await publicLawConstitutional(),
          details: const ResearchDetailsData(publishingEntity: 'جهة'),
        ),
      );
      expect((await approve.call(id)).isValid, isTrue);

      final int id2 = await insertDocument(db);
      await addHealthySource(db, id2);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id2,
          common: await validCommon('research_paper'),
          primaryClassification: await publicLawConstitutional(),
          details: const ResearchDetailsData(),
        ),
      );
      expect((await approve.call(id2)).hasError('research'), isTrue);
    });

    test('legislation: type, country, and year OR date', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      final common = (await validCommon(
        'legislation',
      )).copyWith(countryKey: 'ps', publicationYear: 2020);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: common,
          primaryClassification: await publicLawConstitutional(),
          details: const LegislationDetailsData(
            legislationTypeKey: 'ordinary_legislation',
          ),
        ),
      );
      expect((await approve.call(id)).isValid, isTrue);

      // Missing country fails.
      final int id2 = await insertDocument(db);
      await addHealthySource(db, id2);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id2,
          common: (await validCommon(
            'legislation',
          )).copyWith(publicationYear: 2020),
          primaryClassification: await publicLawConstitutional(),
          details: const LegislationDetailsData(
            legislationTypeKey: 'ordinary_legislation',
          ),
        ),
      );
      expect((await approve.call(id2)).hasError('countryKey'), isTrue);
    });

    test(
      'court precedent: court, case, country, result OR principle',
      () async {
        final int id = await insertDocument(db);
        await addHealthySource(db, id);
        final common = (await validCommon(
          'court_precedent',
        )).copyWith(countryKey: 'ps');
        await saveDraft.call(
          DraftSaveInput(
            documentId: id,
            common: common,
            primaryClassification: await publicLawConstitutional(),
            details: const CourtCaseDetailsData(
              courtName: 'محكمة',
              caseNumber: '12/2020',
              legalPrinciple: 'مبدأ',
            ),
          ),
        );
        expect((await approve.call(id)).isValid, isTrue);

        final int id2 = await insertDocument(db);
        await addHealthySource(db, id2);
        await saveDraft.call(
          DraftSaveInput(
            documentId: id2,
            common: (await validCommon(
              'court_precedent',
            )).copyWith(countryKey: 'ps'),
            primaryClassification: await publicLawConstitutional(),
            details: const CourtCaseDetailsData(courtName: 'محكمة'),
          ),
        );
        final r = await approve.call(id2);
        expect(r.hasError('courtCase.caseNumber'), isTrue);
        expect(r.hasError('courtCase'), isTrue);
      },
    );

    test('institutional report: requires publishing entity', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('institutional_report'),
          primaryClassification: await publicLawConstitutional(),
          details: const ReportDetailsData(publishingEntity: 'مؤسسة'),
        ),
      );
      expect((await approve.call(id)).isValid, isTrue);

      final int id2 = await insertDocument(db);
      await addHealthySource(db, id2);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id2,
          common: await validCommon('institutional_report'),
          primaryClassification: await publicLawConstitutional(),
          details: const ReportDetailsData(),
        ),
      );
      expect(
        (await approve.call(id2)).hasError('report.publishingEntity'),
        isTrue,
      );
    });

    test('other: requires title and review notes', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: (await validCommon(
            'other',
          )).copyWith(reviewNotes: 'توضيح النوع'),
          primaryClassification: await publicLawConstitutional(),
        ),
      );
      expect((await approve.call(id)).isValid, isTrue);

      final int id2 = await insertDocument(db);
      await addHealthySource(db, id2);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id2,
          common: await validCommon('other'),
          primaryClassification: await publicLawConstitutional(),
        ),
      );
      expect((await approve.call(id2)).hasError('reviewNotes'), isTrue);
    });
  });

  group('ApproveClassification — classification & references', () {
    test('subcategory required when main has active subcategories', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('book'),
          primaryClassification: DocumentClassificationInput(
            mainCategoryId: await mainId(db, 'public_law'),
          ),
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      expect(
        (await approve.call(
          id,
        )).hasError('primaryClassification.subCategoryId'),
        isTrue,
      );
    });

    test(
      'subcategory not required when main has no active subcategories',
      () async {
        // Deactivate every subcategory under islamic_jurisprudence.
        final int islamic = await mainId(db, 'islamic_jurisprudence');
        await (db.update(db.subCategories)
              ..where((s) => s.mainCategoryId.equals(islamic)))
            .write(const SubCategoriesCompanion(isActive: Value(false)));

        final int id = await insertDocument(db);
        await addHealthySource(db, id);
        await saveDraft.call(
          DraftSaveInput(
            documentId: id,
            common: await validCommon('book'),
            primaryClassification: DocumentClassificationInput(
              mainCategoryId: islamic,
            ),
            details: const BookDetailsData(author: 'مؤلف'),
          ),
        );
        expect((await approve.call(id)).isValid, isTrue);
      },
    );

    test('inactive reference is rejected at approval', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('book'),
          primaryClassification: await publicLawConstitutional(),
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      // Deactivate the Arabic language after a valid draft was saved.
      await (db.update(db.languages)..where((l) => l.key.equals('ar'))).write(
        const LanguagesCompanion(isActive: Value(false)),
      );
      final r = await approve.call(id);
      expect(r.hasError('languageKey'), isTrue);
      expect(r.hasCode('invalid_reference'), isTrue);
    });
  });

  group('ApproveClassification — acceptable file', () {
    Future<int> approvableBookWithoutFile() async {
      final int id = await insertDocument(db);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('book'),
          primaryClassification: await publicLawConstitutional(),
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      return id;
    }

    test('no files fails the acceptable-file rule', () async {
      final int id = await approvableBookWithoutFile();
      expect((await approve.call(id)).hasCode('no_acceptable_file'), isTrue);
    });

    test('corrupted source does not satisfy approval', () async {
      final int id = await approvableBookWithoutFile();
      await addFile(db, id, role: 'source_original', health: 'corrupted');
      expect((await approve.call(id)).hasCode('no_acceptable_file'), isTrue);
    });

    test('healthy source satisfies approval', () async {
      final int id = await approvableBookWithoutFile();
      await addHealthySource(db, id);
      expect((await approve.call(id)).isValid, isTrue);
    });

    test('healthy approved converted pdf satisfies approval', () async {
      final int id = await approvableBookWithoutFile();
      final int conv = await addFile(
        db,
        id,
        role: 'converted_pdf',
        health: 'healthy',
      );
      await addConversion(
        db,
        id,
        conv,
        statusKey: 'conversion_approved',
        qualityApproved: true,
      );
      expect((await approve.call(id)).isValid, isTrue);
    });

    test('conversion_failed with qualityApproved=true is rejected', () async {
      final int id = await approvableBookWithoutFile();
      final int conv = await addFile(
        db,
        id,
        role: 'converted_pdf',
        health: 'healthy',
      );
      // quality_approved alone must never make a failed conversion acceptable.
      await addConversion(
        db,
        id,
        conv,
        statusKey: 'conversion_failed',
        qualityApproved: true,
      );
      expect((await approve.call(id)).hasCode('no_acceptable_file'), isTrue);
    });

    test('unapproved converted pdf does not satisfy approval', () async {
      final int id = await approvableBookWithoutFile();
      final int conv = await addFile(
        db,
        id,
        role: 'converted_pdf',
        health: 'healthy',
      );
      await addConversion(db, id, conv, statusKey: 'needs_conversion_review');
      expect((await approve.call(id)).hasCode('no_acceptable_file'), isTrue);
    });

    test('unhealthy converted pdf does not satisfy approval', () async {
      final int id = await approvableBookWithoutFile();
      final int conv = await addFile(
        db,
        id,
        role: 'converted_pdf',
        health: 'corrupted',
      );
      await addConversion(
        db,
        id,
        conv,
        statusKey: 'conversion_approved',
        qualityApproved: true,
      );
      expect((await approve.call(id)).hasCode('no_acceptable_file'), isTrue);
    });
  });

  group('ApproveClassification — effects', () {
    Future<int> validBook() async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('book'),
          primaryClassification: await publicLawConstitutional(),
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      return id;
    }

    test('success sets classified status and UTC timestamps', () async {
      final int id = await validBook();
      expect((await approve.call(id)).isValid, isTrue);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(doc.workflowStatusKey, 'classified');
      expect(doc.classifiedAt, '2026-06-07T00:00:00.000Z');
      expect(doc.updatedAt, '2026-06-07T00:00:00.000Z');
    });

    test('failed approval changes nothing', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('book'),
          primaryClassification: await publicLawConstitutional(),
          details: const BookDetailsData(), // missing author
        ),
      );
      final before = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect((await approve.call(id)).isInvalid, isTrue);
      final after = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(after.workflowStatusKey, 'in_progress');
      expect(after.classifiedAt, isNull);
      expect(after.updatedAt, before.updatedAt);
    });

    test('approval creates no document code, files, or file events', () async {
      final int id = await validBook();
      final int filesBefore = (await db.select(db.documentFiles).get()).length;
      await approve.call(id);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(doc.documentCode, isNull);
      expect((await db.select(db.documentFiles).get()).length, filesBefore);
      expect(await db.select(db.fileEvents).get(), isEmpty);
    });

    test('approving a missing document returns not_found', () async {
      expect((await approve.call(999999)).hasCode('not_found'), isTrue);
    });
  });

  group('ApproveClassification — persisted field validation', () {
    test('rejects persisted overlong text', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('book'),
          primaryClassification: await publicLawConstitutional(),
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      // Corrupt the persisted title directly, bypassing save normalization.
      await (db.update(db.documents)..where((d) => d.id.equals(id))).write(
        DocumentsCompanion(title: Value('x' * 501)),
      );
      final r = await approve.call(id);
      expect(r.hasError('title'), isTrue);
      expect(r.hasCode('too_long'), isTrue);
    });

    test('rejects persisted control-character text', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: await validCommon('book'),
          primaryClassification: await publicLawConstitutional(),
          details: const BookDetailsData(author: 'مؤلف'),
        ),
      );
      await (db.update(db.documents)..where((d) => d.id.equals(id))).write(
        const DocumentsCompanion(title: Value('عنوان\tسيئ')),
      );
      expect((await approve.call(id)).hasCode('invalid_chars'), isTrue);
    });

    test('rejects persisted invalid ISO date', () async {
      final int id = await insertDocument(db);
      await addHealthySource(db, id);
      await saveDraft.call(
        DraftSaveInput(
          documentId: id,
          common: (await validCommon(
            'legislation',
          )).copyWith(countryKey: 'ps', publicationYear: 2020),
          primaryClassification: await publicLawConstitutional(),
          details: const LegislationDetailsData(
            legislationTypeKey: 'ordinary_legislation',
          ),
        ),
      );
      // Corrupt the persisted publication date directly.
      await (db.update(
        db.legislationDetails,
      )..where((l) => l.documentId.equals(id))).write(
        const LegislationDetailsCompanion(publicationDate: Value('2026-13-40')),
      );
      final r = await approve.call(id);
      expect(r.hasError('legislation.publicationDate'), isTrue);
      expect(r.hasCode('invalid_date'), isTrue);
    });
  });
}
