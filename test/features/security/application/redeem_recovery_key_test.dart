import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/redeem_recovery_key.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_status.dart';
import 'package:legal_library_manager/features/security/domain/entities/failed_login_state.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';

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
  late SessionManager sessionManager;
  late RedeemRecoveryKey useCase;

  const minimalHasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 12));

  late String recoveryKey;

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    sessionManager = SessionManager();

    useCase = RedeemRecoveryKey(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
    );

    await BootstrapAdminAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    ).call();

    // SetInitialAdminPassword also stores a recovery key hash — capture it.
    recoveryKey = await SetInitialAdminPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
    ).call('AdminPass1');
  });

  tearDown(() async {
    sessionManager.dispose();
    await db.close();
  });

  group('RedeemRecoveryKey', () {
    test('valid key resets admin to mustChangePassword=true', () async {
      await useCase.call(recoveryKey);
      final admin = await accountRepo.findById('admin');
      expect(admin!.mustChangePassword, isTrue);
    });

    test('valid key lifts any suspension on the admin account', () async {
      final admin = await accountRepo.findById('admin');
      await accountRepo.updateAccount(
        admin!.copyWith(status: AccountStatus.suspended),
      );
      await useCase.call(recoveryKey);
      final updated = await accountRepo.findById('admin');
      expect(updated!.status, AccountStatus.active);
    });

    test('valid key invalidates the active session', () async {
      sessionManager.login(Session(
        accountId: 'admin',
        username: 'marjiy@admin',
        role: AccountRole.admin,
        startedAt: clock.nowUtc(),
      ));
      expect(sessionManager.currentSession, isNotNull);
      await useCase.call(recoveryKey);
      expect(sessionManager.currentSession, isNull);
    });

    test('valid key resets security state (failures + recovery attempts)',
        () async {
      await accountRepo.upsertSecurityState(
        'admin',
        const FailedLoginState(
          consecutiveFailures: 3,
          recoveryAttemptCount: 2,
        ),
      );
      await useCase.call(recoveryKey);
      final state = await accountRepo.getSecurityState('admin');
      expect(state?.consecutiveFailures, 0);
      expect(state?.recoveryAttemptCount, 0);
    });

    test('valid key rotates the recovery credential (new hash stored)', () async {
      final hashBefore = await accountRepo.getRecoveryKeyHash('admin');
      final newKey = await useCase.call(recoveryKey);
      final hashAfter = await accountRepo.getRecoveryKeyHash('admin');
      expect(hashAfter, isNot(equals(hashBefore)));
      // The new key verifies against the new hash.
      expect(
        await minimalHasher.verify(newKey, hashAfter!),
        isTrue,
      );
    });

    test('valid key returns new raw recovery key in correct format', () async {
      final newKey = await useCase.call(recoveryKey);
      expect(
        newKey,
        matches(RegExp(r'^[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}$')),
      );
    });

    test('valid key records recovery_key_redeemed audit event', () async {
      await useCase.call(recoveryKey);
      final events = await auditRepo.loadEvents(limit: 20, offset: 0);
      expect(
        events.any((e) => e.eventTypeKey == 'recovery_key_redeemed'),
        isTrue,
      );
    });

    test('throws InvalidRecoveryKeyException for wrong key', () async {
      expect(
        () => useCase.call('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD'),
        throwsA(isA<InvalidRecoveryKeyException>()),
      );
    });

    test('throws InvalidRecoveryKeyException when no credentials stored',
        () async {
      final db2 = AppDatabase.inMemory();
      final repo2 = DriftAccountRepository(db2);
      final audit2 = DriftSecurityAuditRepository(db2);
      final sm2 = SessionManager();
      try {
        await BootstrapAdminAccount(
          accounts: repo2,
          auditLog: audit2,
          clock: clock,
        ).call();
        final useCase2 = RedeemRecoveryKey(
          accounts: repo2,
          hasher: minimalHasher,
          auditLog: audit2,
          clock: clock,
          sessionManager: sm2,
        );
        await expectLater(
          useCase2.call(recoveryKey),
          throwsA(isA<InvalidRecoveryKeyException>()),
        );
      } finally {
        sm2.dispose();
        await db2.close();
      }
    });

    test('increments recovery attempt count on wrong key', () async {
      try {
        await useCase.call('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD');
      } on InvalidRecoveryKeyException {
        // expected
      }
      final state = await accountRepo.getSecurityState('admin');
      expect(state!.recoveryAttemptCount, 1);
    });

    test('throws RecoveryKeyThrottledException after max attempts in window',
        () async {
      for (var i = 0; i < 3; i++) {
        try {
          await useCase.call('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD');
        } on InvalidRecoveryKeyException {
          // expected each time
        }
      }
      expect(
        () => useCase.call('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD'),
        throwsA(isA<RecoveryKeyThrottledException>()),
      );
    });
  });
}
