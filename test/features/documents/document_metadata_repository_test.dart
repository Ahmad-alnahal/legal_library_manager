// test/features/documents/document_metadata_repository_test.dart

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_document_metadata_repository.dart';
import 'package:legal_library_manager/features/duplicates/data/repositories/drift_duplicate_review_repository.dart';

void main() {
  group('DriftDocumentMetadataRepository — preferred source & duplicates', () {
    late AppDatabase db;
    late DriftDocumentMetadataRepository metaRepo;
    late DriftDuplicateReviewRepository dupRepo;

    const now = '2026-06-26T10:00:00.000Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      metaRepo = DriftDocumentMetadataRepository(db);
      dupRepo = DriftDuplicateReviewRepository(db);
    });

    tearDown(() => db.close());

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    Future<int> addDocument({String? title}) => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            title: Value(title),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<int> addSourceFile(
      int documentId, {
      required String name,
      required String path,
      String health = 'healthy',
      String extension = '.pdf',
      bool isPreferred = false,
    }) => db
        .into(db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            documentId: documentId,
            fileRoleKey: 'source_original',
            fileName: name,
            absolutePath: path,
            extension: extension,
            fileSizeBytes: 1024,
            fileHealthKey: Value(health),
            isPreferred: Value(isPreferred),
            isReadOnlySource: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<int> addDuplicateGroup(String hash, {int? preferredFileId}) => db
        .into(db.duplicateGroups)
        .insert(
          DuplicateGroupsCompanion.insert(
            groupCode: 'GRP-$hash',
            sha256Hash: hash,
            preferredFileId: Value(preferredFileId),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<void> addGroupMember(
      int groupId,
      int fileId, {
      bool hidden = false,
    }) => db
        .into(db.duplicateGroupMembers)
        .insert(
          DuplicateGroupMembersCompanion.insert(
            duplicateGroupId: groupId,
            fileId: fileId,
            isHiddenFromSearch: Value(hidden),
            addedAt: now,
          ),
        );

    // ---------------------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------------------

    test(
      'loadAggregate preferredSourceFileName reflects document_files.is_preferred',
      () async {
        final docId = await addDocument(title: 'وثيقة');
        await addSourceFile(docId, name: 'a.pdf', path: '/agg-a.pdf');
        await addSourceFile(
          docId,
          name: 'b.pdf',
          path: '/agg-b.pdf',
          isPreferred: true,
        );

        final agg = await metaRepo.loadAggregate(docId);

        expect(agg, isNotNull);
        expect(agg!.preferredSourceFileName, 'b.pdf');
      },
    );

    test('loadAggregate uses duplicate-group preferred_file_id as fallback '
        'when document_files.is_preferred is not set', () async {
      // Simulates legacy data: preferred_file_id is recorded on the group but
      // document_files.is_preferred was never synced.
      final docId = await addDocument();
      final fileA = await addSourceFile(
        docId,
        name: 'a.pdf',
        path: '/leg-a.pdf',
      );
      final fileB = await addSourceFile(
        docId,
        name: 'b.pdf',
        path: '/leg-b.pdf',
      );

      // Neither file has is_preferred=true; group points at fileB.
      final groupId = await addDuplicateGroup(
        'leg-hash',
        preferredFileId: fileB,
      );
      await addGroupMember(groupId, fileA);
      await addGroupMember(groupId, fileB);

      final agg = await metaRepo.loadAggregate(docId);

      expect(agg!.preferredSourceFileName, 'b.pdf');
    });

    test('loadAggregate hides non-preferred hidden duplicate and includes the '
        'chosen favorite', () async {
      final docId = await addDocument();
      final favorite = await addSourceFile(
        docId,
        name: 'favorite.pdf',
        path: '/fav.pdf',
        isPreferred: true,
      );
      final hiddenOther = await addSourceFile(
        docId,
        name: 'hidden-other.pdf',
        path: '/hidden-other.pdf',
      );

      final groupId = await addDuplicateGroup(
        'hide-test',
        preferredFileId: favorite,
      );
      await addGroupMember(groupId, favorite);
      await addGroupMember(groupId, hiddenOther, hidden: true);

      final agg = await metaRepo.loadAggregate(docId);

      final sourceIds = agg!.files
          .where((f) => f.fileRoleKey == 'source_original')
          .map((f) => f.id)
          .toList();
      expect(sourceIds, contains(favorite));
      expect(sourceIds, isNot(contains(hiddenOther)));
      expect(agg.preferredSourceFileName, 'favorite.pdf');
    });

    test(
      'regression: set preferred + hide other → loadAggregate shows favorite',
      () async {
        // Full round-trip through DriftDuplicateReviewRepository so the same
        // code path used in production is exercised.
        final docId = await addDocument(title: 'قرار');
        final fileA = await addSourceFile(
          docId,
          name: 'a.pdf',
          path: '/reg-a.pdf',
        );
        final fileB = await addSourceFile(
          docId,
          name: 'b.pdf',
          path: '/reg-b.pdf',
        );
        final groupId = await addDuplicateGroup('regression-hash');
        await addGroupMember(groupId, fileA);
        await addGroupMember(groupId, fileB);

        // Reviewer chooses fileB as favorite and hides fileA.
        await dupRepo.setPreferredMember(groupId: groupId, fileId: fileB);
        await dupRepo.setMemberHidden(
          groupId: groupId,
          fileId: fileA,
          hidden: true,
        );

        // Classification / edit reopens the document.
        final agg = await metaRepo.loadAggregate(docId);

        expect(
          agg!.preferredSourceFileName,
          'b.pdf',
          reason: 'favorite member must be the preferred source',
        );
        final sourceIds = agg.files
            .where((f) => f.fileRoleKey == 'source_original')
            .map((f) => f.id)
            .toList();
        expect(
          sourceIds,
          isNot(contains(fileA)),
          reason: 'hidden non-preferred member must be excluded',
        );
        expect(sourceIds, contains(fileB));
      },
    );
  });
}
