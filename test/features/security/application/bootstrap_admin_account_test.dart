import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_status.dart';

class _FixedClock extends Clock {
  const _FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime nowUtc() => _now;
}

void main() {
  late AppDatabase db;
  late DriftAccountRepository accountRepo;
  late DriftSecurityAuditRepository auditRepo;
  late BootstrapAdminAccount useCase;

  final fixedNow = DateTime.utc(2026, 6, 23, 10);

  setUp(() {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    useCase = BootstrapAdminAccount(
      accounts: accountRepo, // external name strips '_' per Dart convention
      auditLog: auditRepo,
      clock: _FixedClock(fixedNow),
    );
  });

  tearDown(() async => db.close());

  group('BootstrapAdminAccount', () {
    test('creates the admin account on first call', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      expect(admin, isNotNull);
    });

    test('admin account has correct internalId and username', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      expect(admin!.internalId, 'admin');
      expect(admin.username, 'marjiy@admin');
    });

    test('admin account has arabic display name', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      expect(admin!.displayName, 'مدير النظام');
    });

    test('admin account has role=admin, status=active', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      expect(admin!.role, AccountRole.admin);
      expect(admin.status, AccountStatus.active);
    });

    test('admin account has mustChangePassword=true', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      expect(admin!.mustChangePassword, isTrue);
    });

    test('admin password hash is not empty and is not plaintext', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      expect(admin!.passwordHash, isNotEmpty);
      expect(admin.passwordHash, isNot(equals('admin')));
      expect(admin.passwordHash, isNot(equals('password')));
      expect(admin.passwordHash, isNot(equals('marjiy')));
    });

    test('sentinel hash cannot be verified by any password', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      // The password hasher with minimal params to keep the test fast.
      const hasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
      expect(
        await hasher.verify('anything', admin!.passwordHash),
        isFalse,
        reason: 'sentinel hash must not be verifiable',
      );
      expect(await hasher.verify('', admin.passwordHash), isFalse);
    });

    test('createdAt and updatedAt are set to the clock time', () async {
      await useCase.call();
      final admin = await accountRepo.findById('admin');
      expect(admin!.createdAt, fixedNow);
      expect(admin.updatedAt, fixedNow);
    });

    test('records an admin_bootstrapped audit event', () async {
      await useCase.call();
      final events = await auditRepo.loadEvents(limit: 10, offset: 0);
      expect(events.length, 1);
      expect(events.first.eventTypeKey, 'admin_bootstrapped');
      expect(events.first.actorAccountId, 'admin');
    });

    test(
      'is idempotent: calling twice does not duplicate the account',
      () async {
        await useCase.call();
        await useCase.call();
        // findByUsername uniquely identifies the account; if a duplicate were
        // inserted the unique index would have thrown, but double-check count.
        final admin = await accountRepo.findByUsername('marjiy@admin');
        expect(admin, isNotNull);
        // Audit log gets only one entry (second call returns early).
        final events = await auditRepo.loadEvents(limit: 10, offset: 0);
        expect(
          events.length,
          1,
          reason: 'audit log must have exactly one bootstrap event',
        );
      },
    );

    test(
      'is idempotent: calling twice does not record a second audit event',
      () async {
        await useCase.call();
        await useCase.call();
        final events = await auditRepo.loadEvents(limit: 10, offset: 0);
        expect(
          events.where((e) => e.eventTypeKey == 'admin_bootstrapped').length,
          1,
        );
      },
    );
  });
}
