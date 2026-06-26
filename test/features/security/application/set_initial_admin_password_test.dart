import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/services/password_hasher.dart';

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
  late PasswordHasher hasher;
  late SetInitialAdminPassword useCase;

  const minimalHasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 10));

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    hasher = minimalHasher;
    useCase = SetInitialAdminPassword(
      accounts: accountRepo,
      hasher: hasher,
      auditLog: auditRepo,
      clock: clock,
    );

    await BootstrapAdminAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    ).call();
  });

  tearDown(() async => db.close());

  group('SetInitialAdminPassword', () {
    test('hashes and stores the new password', () async {
      await useCase.call('SecurePass1');
      final admin = await accountRepo.findById('admin');
      expect(admin!.passwordHash, startsWith('\$argon2id'));
    });

    test('sets mustChangePassword to false', () async {
      await useCase.call('SecurePass1');
      final admin = await accountRepo.findById('admin');
      expect(admin!.mustChangePassword, isFalse);
    });

    test('allows login with the new password', () async {
      await useCase.call('SecurePass1');
      final admin = await accountRepo.findById('admin');
      final valid = await hasher.verify('SecurePass1', admin!.passwordHash);
      expect(valid, isTrue);
    });

    test('rejects the old sentinel hash after password change', () async {
      final adminBefore = await accountRepo.findById('admin');
      final sentinelHash = adminBefore!.passwordHash;
      await useCase.call('SecurePass1');
      final adminAfter = await accountRepo.findById('admin');
      expect(adminAfter!.passwordHash, isNot(equals(sentinelHash)));
    });

    test('generates and stores a recovery key hash', () async {
      await useCase.call('SecurePass1');
      final hasCreds = await accountRepo.hasRecoveryCredentials('admin');
      expect(hasCreds, isTrue);
    });

    test('returns the raw recovery key for display', () async {
      final key = await useCase.call('SecurePass1');
      expect(key, isNotEmpty);
      expect(key.length, greaterThan(10));
    });

    test('recovery key has expected dashed hex format', () async {
      final key = await useCase.call('SecurePass1');
      // Format: XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX (4 groups of 8 hex chars)
      final pattern = RegExp(
        r'^[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}$',
      );
      expect(
        pattern.hasMatch(key),
        isTrue,
        reason: 'Key "$key" does not match expected format',
      );
    });

    test('recovery key is not stored as-is in the DB', () async {
      final key = await useCase.call('SecurePass1');
      // The raw key must never appear in the DB — only its hash.
      final admin = await accountRepo.findById('admin');
      expect(admin!.passwordHash, isNot(contains(key)));
    });

    test(
      'throws WeakPasswordException for passwords shorter than 8 chars',
      () async {
        expect(
          () => useCase.call('Short'),
          throwsA(isA<WeakPasswordException>()),
        );
      },
    );

    test('records a password_changed audit event', () async {
      await useCase.call('SecurePass1');
      final events = await auditRepo.loadEvents(limit: 10, offset: 0);
      expect(events.any((e) => e.eventTypeKey == 'password_changed'), isTrue);
    });

    test('calling twice generates a new recovery key each time', () async {
      final key1 = await useCase.call('SecurePass1');
      final key2 = await useCase.call('SecurePass2');
      expect(key1, isNot(equals(key2)));
    });
  });
}
