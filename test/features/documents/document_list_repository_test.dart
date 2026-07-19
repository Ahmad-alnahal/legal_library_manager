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

    Future<void> markDuplicate(
      int fileId, {
      bool hiddenFromSearch = false,
    }) async {
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
              isHiddenFromSearch: Value(hiddenFromSearch),
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

    test('FTS search covers metadata, keywords, and file names with AND '
        'semantics across tokens', () async {
      // No leading "ال" (definite article) on "عمل"/"أردني": FTS5's
      // unicode61 tokenizer (per the P4 spec) does not strip Arabic
      // definite-article prefixes, so a prefix match on "عمل*" would not
      // find a token like "العمل".
      final metadata = await addDocument(
        title: 'قانون عمل أردني',
        summary: 'مرجع فلسطيني',
        code: 'DOC-001',
        updatedAt: now,
      );
      final keyword = await addDocument(title: 'بحث عام', updatedAt: now);
      final file = await addDocument(title: 'وثيقة أخرى', updatedAt: now);
      await addKeyword(keyword, 'عدالة');
      await addFile(
        file,
        name: 'قرار-محكمة.pdf',
        health: 'healthy',
        path: r'C:\archive\قرار-محكمة.pdf',
      );
      // These inserts bypass the write-path repositories that call
      // updateDocumentFts, so the index is synced manually here.
      for (final id in [metadata, keyword, file]) {
        await db.updateDocumentFts(id);
      }

      Future<List<int>> search(String value) async =>
          (await repository.getDocuments(
            DocumentListQuery(filters: DocumentListFilters(search: value)),
          )).items.map((e) => e.id).toList();

      expect(await search('قانون'), [metadata]);
      expect(await search('عمل'), [metadata]);
      expect(await search('قانون عمل'), [metadata]);
      expect(await search('فلسطيني'), [metadata]);
      expect(await search('DOC-001'), [metadata]);
      expect(await search('عدالة'), [keyword]);
      expect(await search('قرار-محكمة'), [file]);
      expect(await search('xyz_not_found'), isEmpty);

      // Whitespace-only after special-character stripping yields no usable
      // tokens, so the search clause is skipped entirely and every document
      // is returned rather than none.
      expect(await search('***'), containsAll([metadata, keyword, file]));

      final all = await repository.getDocuments(const DocumentListQuery());
      expect(
        all.items.map((e) => e.id),
        containsAll([metadata, keyword, file]),
      );
    });

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

    test('sets exactly one healthy PDF source as preferred', () async {
      final documentId = await addDocument(title: 'مرجع', updatedAt: now);
      final first = await addFile(
        documentId,
        name: 'first.pdf',
        health: 'healthy',
        path: r'C:\src\first.pdf',
      );
      final second = await addFile(
        documentId,
        name: 'second.pdf',
        health: 'healthy',
        path: r'C:\src\second.pdf',
      );

      await repository.setPreferredSourceFile(documentId, first);
      await repository.setPreferredSourceFile(documentId, second);

      final files = await repository.getSourceFiles(documentId);
      expect(files.first.id, second);
      expect(files.first.isPreferred, isTrue);
      expect(files.where((file) => file.isPreferred), hasLength(1));
    });

    test('source-file details omit hidden duplicate members', () async {
      final documentId = await addDocument(title: 'مرجع', updatedAt: now);
      final hidden = await addFile(
        documentId,
        name: 'hidden.pdf',
        health: 'healthy',
        path: r'C:\src\hidden.pdf',
      );
      final visible = await addFile(
        documentId,
        name: 'visible.pdf',
        health: 'healthy',
        path: r'C:\src\visible.pdf',
      );
      await markDuplicate(hidden, hiddenFromSearch: true);
      await markDuplicate(visible);

      final files = await repository.getSourceFiles(documentId);

      expect(files.map((file) => file.id), isNot(contains(hidden)));
      expect(files.map((file) => file.id), contains(visible));
    });

    test(
      'rejects an unhealthy preferred source without changing metadata',
      () async {
        final documentId = await addDocument(title: 'مرجع', updatedAt: now);
        final healthy = await addFile(
          documentId,
          name: 'healthy.pdf',
          health: 'healthy',
          path: r'C:\src\healthy.pdf',
        );
        final corrupted = await addFile(
          documentId,
          name: 'corrupted.pdf',
          health: 'corrupted',
          path: r'C:\src\corrupted.pdf',
        );
        await repository.setPreferredSourceFile(documentId, healthy);

        await expectLater(
          repository.setPreferredSourceFile(documentId, corrupted),
          throwsStateError,
        );

        final files = await repository.getSourceFiles(documentId);
        expect(files.singleWhere((file) => file.isPreferred).id, healthy);
      },
    );

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

    test(
      'getSourceFiles orders duplicate-group preferred member first',
      () async {
        final documentId = await addDocument(title: 'مرجع', updatedAt: now);
        // Insert second before first by alpha name — without any preference,
        // file_name ordering would put 'a.pdf' first.
        final fileA = await addFile(
          documentId,
          name: 'a.pdf',
          health: 'healthy',
          path: r'C:\src\pref-a.pdf',
        );
        final fileB = await addFile(
          documentId,
          name: 'b.pdf',
          health: 'healthy',
          path: r'C:\src\pref-b.pdf',
        );

        // Mark fileB as the duplicate-group preferred member (simulates
        // what setPreferredMember does after Fix 1 syncs is_preferred).
        await (db.update(db.documentFiles)..where((f) => f.id.equals(fileB)))
            .write(const DocumentFilesCompanion(isPreferred: Value(true)));

        final groupId = await db
            .into(db.duplicateGroups)
            .insert(
              DuplicateGroupsCompanion.insert(
                groupCode: 'GRP-ORD',
                sha256Hash: 'hash-ord',
                preferredFileId: Value(fileB),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.duplicateGroupMembers)
            .insert(
              DuplicateGroupMembersCompanion.insert(
                duplicateGroupId: groupId,
                fileId: fileA,
                addedAt: now,
              ),
            );
        await db
            .into(db.duplicateGroupMembers)
            .insert(
              DuplicateGroupMembersCompanion.insert(
                duplicateGroupId: groupId,
                fileId: fileB,
                addedAt: now,
              ),
            );

        final files = await repository.getSourceFiles(documentId);
        expect(files.first.id, fileB);
        expect(files.first.isPreferred, isTrue);
        expect(files[1].id, fileA);
      },
    );

    test(
      'getSourceFiles falls back to group preferred_file_id when is_preferred not set',
      () async {
        // Tests the defensive fallback: preferred_file_id is set on the group
        // but document_files.is_preferred was never synced (legacy data).
        final documentId = await addDocument(title: 'legacy', updatedAt: now);
        final fileA = await addFile(
          documentId,
          name: 'a.pdf',
          health: 'healthy',
          path: r'C:\src\legacy-a.pdf',
        );
        final fileB = await addFile(
          documentId,
          name: 'b.pdf',
          health: 'healthy',
          path: r'C:\src\legacy-b.pdf',
        );

        // No is_preferred set on either file — group level only.
        final groupId = await db
            .into(db.duplicateGroups)
            .insert(
              DuplicateGroupsCompanion.insert(
                groupCode: 'GRP-LEG',
                sha256Hash: 'hash-leg',
                preferredFileId: Value(fileB),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.duplicateGroupMembers)
            .insert(
              DuplicateGroupMembersCompanion.insert(
                duplicateGroupId: groupId,
                fileId: fileA,
                addedAt: now,
              ),
            );
        await db
            .into(db.duplicateGroupMembers)
            .insert(
              DuplicateGroupMembersCompanion.insert(
                duplicateGroupId: groupId,
                fileId: fileB,
                addedAt: now,
              ),
            );

        final files = await repository.getSourceFiles(documentId);
        expect(files.first.id, fileB);
      },
    );

    test(
      'source_file_name in list excludes hidden duplicate members',
      () async {
        final documentId = await addDocument(updatedAt: now);
        // hidden has the lower ID (alphabetically first name) — without
        // exclusion it would be selected as source_file_name.
        final hidden = await addFile(
          documentId,
          name: 'aaa-hidden.pdf',
          health: 'healthy',
          path: r'C:\src\aaa-hidden.pdf',
        );
        await addFile(
          documentId,
          name: 'zzz-visible.pdf',
          health: 'healthy',
          path: r'C:\src\zzz-visible.pdf',
        );
        await markDuplicate(hidden, hiddenFromSearch: true);

        final page = await repository.getDocuments(const DocumentListQuery());
        expect(page.items.single.sourceFileName, 'zzz-visible.pdf');
      },
    );

    test(
      'source_file_name in list respects duplicate-group preferred_file_id',
      () async {
        final documentId = await addDocument(updatedAt: now);
        await addFile(
          documentId,
          name: 'a.pdf',
          health: 'healthy',
          path: r'C:\src\list-a.pdf',
        );
        final fileB = await addFile(
          documentId,
          name: 'b.pdf',
          health: 'healthy',
          path: r'C:\src\list-b.pdf',
        );

        // Simulates setPreferredMember syncing is_preferred.
        await (db.update(db.documentFiles)..where((f) => f.id.equals(fileB)))
            .write(const DocumentFilesCompanion(isPreferred: Value(true)));

        final page = await repository.getDocuments(const DocumentListQuery());
        expect(page.items.single.sourceFileName, 'b.pdf');
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
