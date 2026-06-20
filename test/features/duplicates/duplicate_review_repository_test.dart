// test/features/duplicates/duplicate_review_repository_test.dart

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/duplicates/data/repositories/drift_duplicate_review_repository.dart';

void main() {
  group('DriftDuplicateReviewRepository', () {
    late AppDatabase db;
    late DriftDuplicateReviewRepository repository;

    const now = '2026-06-20T10:00:00.000Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      repository = DriftDuplicateReviewRepository(db);
    });

    tearDown(() => db.close());

    // â”€â”€ helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    Future<int> addDocument({
      String? title,
      String? code,
      String status = 'imported',
    }) => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            title: Value(title),
            documentCode: Value(code),
            workflowStatusKey: Value(status),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<int> addFile(
      int documentId, {
      String name = 'file.pdf',
      String path = '/tmp/file.pdf',
      String health = 'healthy',
      bool isPreferred = false,
    }) => db
        .into(db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            documentId: documentId,
            fileRoleKey: 'source_original',
            fileName: name,
            absolutePath: path,
            extension: '.pdf',
            fileSizeBytes: 1024,
            fileHealthKey: Value(health),
            isPreferred: Value(isPreferred),
            isReadOnlySource: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<int> addGroup({
      required String hash,
      String code = '',
      String status = 'unreviewed',
      String updatedAt = now,
    }) => db
        .into(db.duplicateGroups)
        .insert(
          DuplicateGroupsCompanion.insert(
            groupCode: code.isEmpty ? 'GRP-$hash' : code,
            sha256Hash: hash,
            reviewStatusKey: Value(status),
            createdAt: now,
            updatedAt: updatedAt,
          ),
        );

    Future<void> addMember(int groupId, int fileId) => db
        .into(db.duplicateGroupMembers)
        .insert(
          DuplicateGroupMembersCompanion.insert(
            duplicateGroupId: groupId,
            fileId: fileId,
            addedAt: now,
          ),
        );

    // â”€â”€ getGroups â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    test('returns empty page when no groups exist', () async {
      final page = await repository.getGroups();

      expect(page.groups, isEmpty);
      expect(page.totalCount, 0);
      expect(page.hasMore, isFalse);
    });

    test('excludes groups with fewer than 2 members', () async {
      final doc = await addDocument();
      final file = await addFile(doc, path: '/a.pdf');
      final groupId = await addGroup(hash: 'abc123');
      await addMember(groupId, file);

      final page = await repository.getGroups();

      expect(page.groups, isEmpty);
      expect(page.totalCount, 0);
    });

    test('includes groups with exactly 2 members', () async {
      final doc = await addDocument(title: 'Ù‚Ø§Ù†ÙˆÙ†');
      final f1 = await addFile(doc, path: '/a.pdf');
      final f2 = await addFile(doc, path: '/b.pdf', name: 'b.pdf');
      final groupId = await addGroup(hash: 'deadbeef01');
      await addMember(groupId, f1);
      await addMember(groupId, f2);

      final page = await repository.getGroups();

      expect(page.groups.length, 1);
      expect(page.totalCount, 1);
      expect(page.groups.first.memberCount, 2);
      expect(page.groups.first.sha256Hash, 'deadbeef01');
      expect(page.groups.first.userLabel, isNot(page.groups.first.groupCode));
    });

    test('includes groups whose documents are classified or copied', () async {
      final classified = await addDocument(
        code: 'DOC-CLASSIFIED',
        status: 'classified',
      );
      final copied = await addDocument(
        code: 'DOC-COPIED',
        status: 'copied_to_library',
      );
      final f1 = await addFile(classified, path: '/classified.pdf');
      final f2 = await addFile(copied, path: '/copied.pdf', name: 'copied.pdf');
      final groupId = await addGroup(hash: 'classified-copied');
      await addMember(groupId, f1);
      await addMember(groupId, f2);

      final page = await repository.getGroups();
      final details = await repository.getGroupDetails(groupId);

      expect(page.groups.map((g) => g.id), contains(groupId));
      expect(
        details.members.map((m) => m.workflowStatusKey),
        containsAll(['classified', 'copied_to_library']),
      );
    });

    test(
      'sorts actionable groups first and counts deferred as pending',
      () async {
        // Group A is reviewed and newer; group B is unreviewed and older; group C
        // is deferred. Pending count includes B and C, but not reviewed A.
        final docA = await addDocument();
        final fa1 = await addFile(docA, path: '/a1.pdf');
        final fa2 = await addFile(docA, path: '/a2.pdf', name: 'a2.pdf');
        final gA = await addGroup(
          hash: 'hashA',
          code: 'GRP-A',
          status: 'reviewed',
          updatedAt: '2026-06-20T08:00:00.000Z',
        );
        await addMember(gA, fa1);
        await addMember(gA, fa2);

        final docB = await addDocument(code: 'DOC-002');
        final fb1 = await addFile(docB, path: '/b1.pdf', name: 'b1.pdf');
        final fb2 = await addFile(docB, path: '/b2.pdf', name: 'b2.pdf');
        final gB = await addGroup(
          hash: 'hashB',
          code: 'GRP-B',
          status: 'unreviewed',
          updatedAt: '2026-06-20T07:00:00.000Z',
        );
        await addMember(gB, fb1);
        await addMember(gB, fb2);

        final docC = await addDocument(code: 'DOC-003');
        final fc1 = await addFile(docC, path: '/c1.pdf', name: 'c1.pdf');
        final fc2 = await addFile(docC, path: '/c2.pdf', name: 'c2.pdf');
        final gC = await addGroup(
          hash: 'hashC',
          code: 'GRP-C',
          status: 'archived_for_later',
          updatedAt: '2026-06-20T09:00:00.000Z',
        );
        await addMember(gC, fc1);
        await addMember(gC, fc2);

        final page = await repository.getGroups();

        expect(page.groups[0].groupCode, 'GRP-B');
        expect(page.groups[1].groupCode, 'GRP-C');
        expect(page.groups[2].groupCode, 'GRP-A');
        expect(page.totalCount, 3);
        expect(page.pendingReviewCount, 2);
      },
    );

    test('paginates correctly', () async {
      // Create 3 groups each with 2 files.
      for (var i = 0; i < 3; i++) {
        final doc = await addDocument(code: 'DOC-$i');
        final f1 = await addFile(doc, path: '/$i-a.pdf', name: '$i-a.pdf');
        final f2 = await addFile(doc, path: '/$i-b.pdf', name: '$i-b.pdf');
        final g = await addGroup(hash: 'hash$i', code: 'GRP-$i');
        await addMember(g, f1);
        await addMember(g, f2);
      }

      final page1 = await repository.getGroups(offset: 0, limit: 2);
      expect(page1.groups.length, 2);
      expect(page1.totalCount, 3);
      expect(page1.hasMore, isTrue);

      final page2 = await repository.getGroups(offset: 2, limit: 2);
      expect(page2.groups.length, 1);
      expect(page2.totalCount, 3);
      expect(page2.hasMore, isFalse);
    });

    test('rejects invalid pagination parameters', () async {
      expect(() => repository.getGroups(offset: -1), throwsArgumentError);
      expect(() => repository.getGroups(limit: 0), throwsArgumentError);
      expect(() => repository.getGroups(limit: 201), throwsArgumentError);
    });

    // â”€â”€ getGroupDetails â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    test('getGroupDetails returns group with notes and all members', () async {
      final doc = await addDocument(title: 'Ø¹Ù‚Ø¯', code: 'DOC-0001');
      final f1 = await addFile(doc, path: '/x.pdf', isPreferred: true);
      final f2 = await addFile(doc, path: '/y.pdf', name: 'y.pdf');
      final groupId = await addGroup(hash: 'abc', code: 'GRP-X');

      // Add notes via direct DB update.
      await (db.update(
        db.duplicateGroups,
      )..where((g) => g.id.equals(groupId))).write(
        const DuplicateGroupsCompanion(
          notes: Value('Ù…Ù„Ø§Ø­Ø¸Ø© Ø§Ø®ØªØ¨Ø§Ø±'),
        ),
      );

      await addMember(groupId, f1);
      await addMember(groupId, f2);

      final details = await repository.getGroupDetails(groupId);

      expect(details.summary.groupCode, 'GRP-X');
      expect(details.summary.sha256Hash, 'abc');
      expect(details.summary.userLabel, isNot(details.summary.groupCode));
      expect(details.notes, 'Ù…Ù„Ø§Ø­Ø¸Ø© Ø§Ø®ØªØ¨Ø§Ø±');
      expect(details.members.length, 2);
    });

    test('preferred member appears first in getGroupDetails', () async {
      final doc = await addDocument(title: 'ÙˆØ«ÙŠÙ‚Ø©');
      // Insert non-preferred first, then mark the second as preferred at the
      // duplicate-group level.
      final fNonPref = await addFile(doc, path: '/np.pdf', name: 'np.pdf');
      final fPref = await addFile(doc, path: '/pref.pdf', name: 'pref.pdf');
      final groupId = await addGroup(hash: 'pref-test');
      await addMember(groupId, fNonPref);
      await addMember(groupId, fPref);
      await repository.setPreferredMember(groupId: groupId, fileId: fPref);

      final details = await repository.getGroupDetails(groupId);

      expect(details.members.first.fileId, fPref);
      expect(details.members.first.isPreferred, isTrue);
      expect(details.members.last.isPreferred, isFalse);
    });

    test('maps document title and code into member', () async {
      final doc = await addDocument(
        title: 'Ù‚Ø§Ù†ÙˆÙ† Ø§Ù„Ø£Ø­ÙˆØ§Ù„',
        code: 'DOC-999',
      );
      final f1 = await addFile(doc, path: '/p1.pdf');
      final f2 = await addFile(doc, path: '/p2.pdf', name: 'p2.pdf');
      final groupId = await addGroup(hash: 'meta-test');
      await addMember(groupId, f1);
      await addMember(groupId, f2);

      final details = await repository.getGroupDetails(groupId);
      final member = details.members.first;

      expect(member.documentCode, 'DOC-999');
      expect(member.documentTitle, 'Ù‚Ø§Ù†ÙˆÙ† Ø§Ù„Ø£Ø­ÙˆØ§Ù„');
      expect(member.displayName, 'Ù‚Ø§Ù†ÙˆÙ† Ø§Ù„Ø£Ø­ÙˆØ§Ù„');
    });

    test('displayName falls back to fileName when title is null', () async {
      final doc = await addDocument(); // no title, no code
      final f1 = await addFile(doc, path: '/noname1.pdf', name: 'noname1.pdf');
      final f2 = await addFile(doc, path: '/noname2.pdf', name: 'noname2.pdf');
      final groupId = await addGroup(hash: 'fallback');
      await addMember(groupId, f1);
      await addMember(groupId, f2);

      final details = await repository.getGroupDetails(groupId);

      expect(details.members.first.displayName, isNotEmpty);
      expect(
        details.members.first.displayName,
        isNot('Ù…Ø³ØªÙ†Ø¯ Ø¨Ù„Ø§ Ø¹Ù†ÙˆØ§Ù†'),
        reason: 'fileName is available so the fallback should not be used',
      );
    });

    test('getGroupDetails throws StateError for unknown groupId', () async {
      expect(
        () => repository.getGroupDetails(999999),
        throwsA(isA<StateError>()),
      );
    });

    test('isHiddenFromSearch is mapped from the members table', () async {
      final doc = await addDocument();
      final f1 = await addFile(doc, path: '/h1.pdf');
      final f2 = await addFile(doc, path: '/h2.pdf', name: 'h2.pdf');
      final groupId = await addGroup(hash: 'hidden-test');

      // Insert f1 with hidden=true.
      await db
          .into(db.duplicateGroupMembers)
          .insert(
            DuplicateGroupMembersCompanion.insert(
              duplicateGroupId: groupId,
              fileId: f1,
              isHiddenFromSearch: const Value(true),
              addedAt: now,
            ),
          );
      await addMember(groupId, f2);

      final details = await repository.getGroupDetails(groupId);

      // Preferred ordering: both not preferred, order by document_code then id.
      // f1 was inserted first â†’ lower id â†’ second after f2 by id ordering.
      // Actually the ORDER is: is_preferred DESC, document_code ASC, id ASC.
      // Both have no document_code and same order by id: f1 < f2.
      final hiddenMember = details.members.firstWhere((m) => m.fileId == f1);
      expect(hiddenMember.isHiddenFromSearch, isTrue);

      final visibleMember = details.members.firstWhere((m) => m.fileId == f2);
      expect(visibleMember.isHiddenFromSearch, isFalse);
    });

    test(
      'setPreferredMember requires membership and updates group preference',
      () async {
        final doc = await addDocument();
        final f1 = await addFile(doc, path: '/pref-a.pdf');
        final f2 = await addFile(doc, path: '/pref-b.pdf', name: 'pref-b.pdf');
        final outsider = await addFile(
          doc,
          path: '/outsider.pdf',
          name: 'outsider.pdf',
        );
        final groupId = await addGroup(hash: 'decision-pref');
        await addMember(groupId, f1);
        await addMember(groupId, f2);

        await repository.setPreferredMember(groupId: groupId, fileId: f2);
        final details = await repository.getGroupDetails(groupId);

        expect(details.summary.preferredFileId, f2);
        expect(details.members.first.fileId, f2);
        expect(details.members.first.isPreferred, isTrue);
        expect(
          () =>
              repository.setPreferredMember(groupId: groupId, fileId: outsider),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'setMemberHidden updates only duplicate membership visibility',
      () async {
        final doc = await addDocument();
        final f1 = await addFile(doc, path: '/hide-a.pdf');
        final f2 = await addFile(doc, path: '/hide-b.pdf', name: 'hide-b.pdf');
        final groupId = await addGroup(hash: 'decision-hide');
        await addMember(groupId, f1);
        await addMember(groupId, f2);

        await repository.setMemberHidden(
          groupId: groupId,
          fileId: f1,
          hidden: true,
        );
        var details = await repository.getGroupDetails(groupId);
        expect(
          details.members.firstWhere((m) => m.fileId == f1).isHiddenFromSearch,
          isTrue,
        );

        await repository.setMemberHidden(
          groupId: groupId,
          fileId: f1,
          hidden: false,
        );
        details = await repository.getGroupDetails(groupId);
        expect(
          details.members.firstWhere((m) => m.fileId == f1).isHiddenFromSearch,
          isFalse,
        );
      },
    );

    test('updateReview validates status and trims notes', () async {
      final doc = await addDocument();
      final f1 = await addFile(doc, path: '/review-a.pdf');
      final f2 = await addFile(
        doc,
        path: '/review-b.pdf',
        name: 'review-b.pdf',
      );
      final groupId = await addGroup(hash: 'decision-review');
      await addMember(groupId, f1);
      await addMember(groupId, f2);

      await repository.updateReview(
        groupId: groupId,
        statusKey: 'reviewed',
        notes: '  checked manually  ',
      );
      var details = await repository.getGroupDetails(groupId);
      expect(details.summary.reviewStatusKey, 'reviewed');
      expect(details.notes, 'checked manually');

      await repository.updateReview(
        groupId: groupId,
        statusKey: 'archived_for_later',
        notes: '   ',
      );
      details = await repository.getGroupDetails(groupId);
      expect(details.summary.reviewStatusKey, 'archived_for_later');
      expect(details.notes, isNull);

      expect(
        () => repository.updateReview(groupId: groupId, statusKey: 'bogus'),
        throwsArgumentError,
      );
    });
  });
}
