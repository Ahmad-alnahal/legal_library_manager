import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_document_list_repository.dart';
import 'package:legal_library_manager/features/documents/domain/entities/document_list_query.dart';

void main() {
  group('DriftDocumentListRepository', () {
    late AppDatabase db;
    late DriftDocumentListRepository repository;
    late int bookTypeId;
    late int publicLawId;
    late int constitutionalId;

    const now = '2026-06-09T12:00:00.000Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      repository = DriftDocumentListRepository(db);
      bookTypeId = (await (db.select(
        db.documentTypes,
      )..where((t) => t.key.equals('book'))).getSingle()).id;
      publicLawId = (await (db.select(
        db.mainCategories,
      )..where((t) => t.key.equals('public_law'))).getSingle()).id;
      constitutionalId = (await (db.select(
        db.subCategories,
      )..where((t) => t.key.equals('constitutional_law'))).getSingle()).id;
    });

    tearDown(() => db.close());

    Future<int> addDocument({
      String? title,
      required String updatedAt,
      String status = 'imported',
      String country = 'ps',
      String trust = 'unverified',
      int? typeId,
      int? mainId,
      int? subId,
      int? year,
      String? summary,
      String? code,
    }) {
      return db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              title: Value(title),
              documentCode: Value(code),
              documentTypeId: Value(typeId),
              primaryMainCategoryId: Value(mainId),
              primarySubCategoryId: Value(subId),
              languageKey: const Value('ar'),
              countryKey: Value(country),
              publicationYear: Value(year),
              summary: Value(summary),
              workflowStatusKey: Value(status),
              trustLevelKey: Value(trust),
              createdAt: now,
              updatedAt: updatedAt,
            ),
          );
    }

    Future<int> addFile(
      int documentId, {
      required String name,
      required String health,
      required String path,
    }) {
      return db
          .into(db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: documentId,
              fileRoleKey: 'source_original',
              fileName: name,
              absolutePath: path,
              extension: '.pdf',
              fileSizeBytes: 100,
              fileHealthKey: Value(health),
              isReadOnlySource: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    Future<void> addKeyword(int documentId, String value) async {
      final keywordId = await db
          .into(db.keywords)
          .insert(
            KeywordsCompanion.insert(
              normalizedValue: value.toLowerCase(),
              displayValue: value,
              createdAt: now,
            ),
          );
      await db
          .into(db.documentKeywords)
          .insert(
            DocumentKeywordsCompanion.insert(
              documentId: documentId,
              keywordId: keywordId,
              createdAt: now,
            ),
          );
    }

    Future<void> markDuplicate(int fileId) async {
      final groupId = await db
          .into(db.duplicateGroups)
          .insert(
            DuplicateGroupsCompanion.insert(
              groupCode: 'DUP-$fileId',
              sha256Hash: 'hash-$fileId',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.duplicateGroupMembers)
          .insert(
            DuplicateGroupMembersCompanion.insert(
              duplicateGroupId: groupId,
              fileId: fileId,
              addedAt: now,
            ),
          );
    }

    test(
      'paginates in stable updated order without loading all rows',
      () async {
        for (var i = 0; i < 7; i++) {
          await addDocument(
            title: 'وثيقة $i',
            updatedAt: '2026-06-0${i + 1}T12:00:00.000Z',
          );
        }

        final first = await repository.getDocuments(
          const DocumentListQuery(limit: 3),
        );
        final second = await repository.getDocuments(
          const DocumentListQuery(offset: 3, limit: 3),
        );

        expect(first.items, hasLength(3));
        expect(second.items, hasLength(3));
        expect(first.totalCount, 7);
        expect(first.hasMore, isTrue);
        expect(first.items.map((e) => e.title), [
          'وثيقة 6',
          'وثيقة 5',
          'وثيقة 4',
        ]);
        expect(second.items.map((e) => e.title), [
          'وثيقة 3',
          'وثيقة 2',
          'وثيقة 1',
        ]);
      },
    );

    test(
      'search covers metadata, keywords, file names, and literal wildcards',
      () async {
        final metadata = await addDocument(
          title: 'القانون الدستوري',
          summary: 'مرجع فلسطيني',
          code: 'DOC-001',
          updatedAt: now,
        );
        final keyword = await addDocument(title: 'بحث عام', updatedAt: now);
        final file = await addDocument(title: 'وثيقة أخرى', updatedAt: now);
        final literal = await addDocument(
          title: 'نسبة 100%_مؤكدة',
          updatedAt: now,
        );
        await addKeyword(keyword, 'عدالة');
        await addFile(
          file,
          name: 'قرار-محكمة.pdf',
          health: 'healthy',
          path: r'C:\archive\قرار-محكمة.pdf',
        );

        Future<List<int>> search(String value) async =>
            (await repository.getDocuments(
              DocumentListQuery(filters: DocumentListFilters(search: value)),
            )).items.map((e) => e.id).toList();

        expect(await search('دستوري'), [metadata]);
        expect(await search('فلسطيني'), [metadata]);
        expect(await search('DOC-001'), [metadata]);
        expect(await search('عدالة'), [keyword]);
        expect(await search('قرار-محكمة'), [file]);
        expect(await search('100%_'), [literal]);
      },
    );

    test('combined filters and derived indicators are accurate', () async {
      final matching = await addDocument(
        title: 'المطابق',
        updatedAt: now,
        status: 'classified',
        trust: 'trusted',
        typeId: bookTypeId,
        mainId: publicLawId,
        subId: constitutionalId,
        year: 2025,
      );
      final duplicateFile = await addFile(
        matching,
        name: 'matching.pdf',
        health: 'corrupted',
        path: r'C:\src\matching.pdf',
      );
      await markDuplicate(duplicateFile);
      await addDocument(
        title: 'غير مطابق',
        updatedAt: '2026-06-08T12:00:00.000Z',
        status: 'imported',
      );

      final page = await repository.getDocuments(
        DocumentListQuery(
          filters: DocumentListFilters(
            workflowStatusKey: 'classified',
            documentTypeId: bookTypeId,
            mainCategoryId: publicLawId,
            subCategoryId: constitutionalId,
            countryKey: 'ps',
            languageKey: 'ar',
            trustLevelKey: 'trusted',
            fileHealthKey: 'corrupted',
            duplicateFilter: DuplicateFilter.duplicatesOnly,
          ),
        ),
      );

      expect(page.totalCount, 1);
      final item = page.items.single;
      expect(item.id, matching);
      expect(item.documentTypeNameAr, 'كتاب');
      expect(item.primaryMainCategoryNameAr, 'القانون العام');
      expect(item.hasDuplicate, isTrue);
      expect(item.hasCorruptedFile, isTrue);
      expect(item.hasUnreadableFile, isFalse);
      expect(item.fileCount, 1);
    });

    test('without-duplicates and source-file details work', () async {
      final plain = await addDocument(title: 'عادي', updatedAt: now);
      final duplicate = await addDocument(
        title: 'مكرر',
        updatedAt: '2026-06-08T12:00:00.000Z',
      );
      await addFile(
        plain,
        name: 'plain.pdf',
        health: 'healthy',
        path: r'C:\src\plain.pdf',
      );
      final duplicateFile = await addFile(
        duplicate,
        name: 'duplicate.pdf',
        health: 'unreadable',
        path: r'C:\src\duplicate.pdf',
      );
      await markDuplicate(duplicateFile);

      final page = await repository.getDocuments(
        const DocumentListQuery(
          filters: DocumentListFilters(
            duplicateFilter: DuplicateFilter.withoutDuplicates,
          ),
        ),
      );
      final files = await repository.getSourceFiles(plain);

      expect(page.items.map((e) => e.id), [plain]);
      expect(files, hasLength(1));
      expect(files.single.absolutePath, r'C:\src\plain.pdf');
      expect(files.single.isReadOnlySource, isTrue);
    });

    test(
      'list item exposes the preferred source filename as title fallback',
      () async {
        final documentId = await addDocument(updatedAt: now);
        await addFile(
          documentId,
          name: 'المرجع القانوني الأصلي.pdf',
          health: 'healthy',
          path: r'C:\src\original.pdf',
        );

        final page = await repository.getDocuments(const DocumentListQuery());

        expect(page.items.single.title, equals(null));
        expect(page.items.single.sourceFileName, 'المرجع القانوني الأصلي.pdf');
      },
    );

    test('invalid pagination is rejected at runtime', () async {
      await expectLater(
        repository.getDocuments(const DocumentListQuery(limit: 201)),
        throwsArgumentError,
      );
    });
  });
}
