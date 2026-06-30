// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('document-type detail tables', () {
    late AppDatabase db;
    const String nowIso = '2026-06-06T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      // Reference rows back the document defaults (trust/usage/quality/status).
      await ReferenceSeeder(db).seedAll();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertDocument() => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(createdAt: nowIso, updatedAt: nowIso),
        );

    test('all six detail tables exist', () async {
      final Set<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      expect(
        tables,
        containsAll(<String>[
          'book_details',
          'thesis_details',
          'research_details',
          'legislation_details',
          'court_case_details',
          'report_details',
        ]),
      );
    });

    test('at most one row per detail table per document', () async {
      final int docId = await insertDocument();
      await db
          .into(db.bookDetails)
          .insert(BookDetailsCompanion.insert(documentId: docId));
      // document_id is the primary key, so a second row is rejected.
      expect(
        () => db
            .into(db.bookDetails)
            .insert(BookDetailsCompanion.insert(documentId: docId)),
        throwsA(isA<SqliteException>()),
      );
    });

    test('incomplete/null detail fields are accepted', () async {
      final int docId = await insertDocument();
      // Only the document_id is provided; every metadata field stays NULL.
      await db
          .into(db.courtCaseDetails)
          .insert(CourtCaseDetailsCompanion.insert(documentId: docId));

      final CourtCaseDetail row = await (db.select(
        db.courtCaseDetails,
      )..where((d) => d.documentId.equals(docId))).getSingle();
      expect(row.courtName, isNull);
      expect(row.caseNumber, isNull);
      expect(row.judgmentResult, isNull);
    });

    test(
      'thesis degree_type_key: valid + NULL accepted, invalid rejected',
      () async {
        final int d1 = await insertDocument();
        await db
            .into(db.thesisDetails)
            .insert(
              ThesisDetailsCompanion.insert(
                documentId: d1,
                degreeTypeKey: const Value('masters'),
              ),
            );
        final int d2 = await insertDocument();
        await db
            .into(db.thesisDetails)
            .insert(
              ThesisDetailsCompanion.insert(
                documentId: d2,
                degreeTypeKey: const Value('doctorate'),
              ),
            );
        final int d3 = await insertDocument();
        // NULL is allowed.
        await db
            .into(db.thesisDetails)
            .insert(
              ThesisDetailsCompanion.insert(
                documentId: d3,
                degreeTypeKey: const Value(null),
              ),
            );

        final int d4 = await insertDocument();
        expect(
          () => db
              .into(db.thesisDetails)
              .insert(
                ThesisDetailsCompanion.insert(
                  documentId: d4,
                  degreeTypeKey: const Value('phd'),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test(
      'legislation constrained keys: valid + NULL accepted, invalid rejected',
      () async {
        final int d1 = await insertDocument();
        await db
            .into(db.legislationDetails)
            .insert(
              LegislationDetailsCompanion.insert(
                documentId: d1,
                legislationTypeKey: const Value('executive_regulation'),
                legislationTypeOther: const Value('تعليمات خاصة'),
                effectiveStatusKey: const Value('active'),
              ),
            );
        final saved = await (db.select(
          db.legislationDetails,
        )..where((row) => row.documentId.equals(d1))).getSingle();
        expect(saved.legislationTypeOther, 'تعليمات خاصة');

        // Both NULL is allowed.
        final int d2 = await insertDocument();
        await db
            .into(db.legislationDetails)
            .insert(LegislationDetailsCompanion.insert(documentId: d2));

        // Invalid legislation type rejected.
        final int d3 = await insertDocument();
        expect(
          () => db
              .into(db.legislationDetails)
              .insert(
                LegislationDetailsCompanion.insert(
                  documentId: d3,
                  legislationTypeKey: const Value('royal_decree'),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );

        // New in v6: 'amended' and 'expired' are now valid effective statuses.
        final int d4 = await insertDocument();
        await db
            .into(db.legislationDetails)
            .insert(
              LegislationDetailsCompanion.insert(
                documentId: d4,
                effectiveStatusKey: const Value('amended'),
              ),
            );
        final int d5 = await insertDocument();
        await db
            .into(db.legislationDetails)
            .insert(
              LegislationDetailsCompanion.insert(
                documentId: d5,
                effectiveStatusKey: const Value('expired'),
              ),
            );

        // Invalid effective status rejected.
        final int d6 = await insertDocument();
        expect(
          () => db
              .into(db.legislationDetails)
              .insert(
                LegislationDetailsCompanion.insert(
                  documentId: d6,
                  effectiveStatusKey: const Value('suspended'),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('deleting a document cascades all detail rows', () async {
      final int docId = await insertDocument();
      await db
          .into(db.bookDetails)
          .insert(BookDetailsCompanion.insert(documentId: docId));
      await db
          .into(db.thesisDetails)
          .insert(ThesisDetailsCompanion.insert(documentId: docId));
      await db
          .into(db.reportDetails)
          .insert(ReportDetailsCompanion.insert(documentId: docId));

      final int deleted = await (db.delete(
        db.documents,
      )..where((d) => d.id.equals(docId))).go();
      expect(deleted, 1);

      expect(await db.select(db.bookDetails).get(), isEmpty);
      expect(await db.select(db.thesisDetails).get(), isEmpty);
      expect(await db.select(db.reportDetails).get(), isEmpty);
    });

    test('a detail row cannot reference a nonexistent document', () async {
      expect(
        () => db
            .into(db.researchDetails)
            .insert(ResearchDetailsCompanion.insert(documentId: 9999)),
        throwsA(isA<SqliteException>()),
      );
    });

    test('an insert that omits document_id is rejected', () async {
      // The typed companion now *requires* document_id (compile-time), so an
      // omission can only be attempted via raw SQL. With WITHOUT ROWID the
      // primary key is NOT NULL and has no rowid fallback, so it is rejected.
      await insertDocument();
      expect(
        () => db.customStatement(
          "INSERT INTO book_details (author) VALUES ('no document id');",
        ),
        throwsA(isA<SqliteException>()),
      );
      // No book_details row was created.
      expect(await db.select(db.bookDetails).get(), isEmpty);
    });
  });
}
