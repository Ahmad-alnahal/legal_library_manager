// test/features/security/application/verify_admin_step_up_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';
import 'package:legal_library_manager/features/security/application/unauthorized_exception.dart';
import 'package:legal_library_manager/features/security/application/verify_admin_step_up.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

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
  late StepUpManager stepUpManager;
  late VerifyAdminStepUp verifyStepUp;

  const minimalHasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 12));
  const adminPassword = 'AdminPass1';

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    stepUpManager = StepUpManager();
    sessionManager = SessionManager(stepUpManager: stepUpManager);

    await BootstrapAdminAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    ).call();
    await SetInitialAdminPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
    ).call(adminPassword);

    verifyStepUp = VerifyAdminStepUp(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
  });

  tearDown(() async {
    stepUpManager.dispose();
    sessionManager.dispose();
    await db.close();
  });

  void loginAsAdmin() {
    sessionManager.login(
      Session(
        accountId: 'admin',
        username: 'marjiy@admin',
        role: AccountRole.admin,
        startedAt: clock.nowUtc(),
      ),
    );
  }

  group('VerifyAdminStepUp', () {
    test('throws UnauthorizedException when no session', () async {
      await expectLater(
        verifyStepUp.call(adminPassword),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(stepUpManager.isApproved, isFalse);
    });

    test('throws UnauthorizedException when operator session', () async {
      sessionManager.login(
        Session(
          accountId: 'some-op',
          username: 'op1',
          role: AccountRole.operator,
          startedAt: clock.nowUtc(),
        ),
      );
      await expectLater(
        verifyStepUp.call(adminPassword),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(stepUpManager.isApproved, isFalse);
    });

    test(
      'returns StepUpVerifySuccess and grants approval on correct password',
      () async {
        loginAsAdmin();
        final result = await verifyStepUp.call(adminPassword);
        expect(result, isA<StepUpVerifySuccess>());
        expect(stepUpManager.isApproved, isTrue);
      },
    );

    test(
      'returns StepUpVerifyWrongPassword and does not grant on wrong password',
      () async {
        loginAsAdmin();
        final result = await verifyStepUp.call('WrongPassword99');
        expect(result, isA<StepUpVerifyWrongPassword>());
        expect(stepUpManager.isApproved, isFalse);
      },
    );

    test(
      'wrong password does not revoke an existing step-up approval',
      () async {
        loginAsAdmin();
        stepUpManager.grant();
        await verifyStepUp.call('WrongPassword99');
        // A wrong attempt must NOT clear existing approval.
        expect(stepUpManager.isApproved, isTrue);
      },
    );

    test('records step_up_granted audit event on success', () async {
      loginAsAdmin();
      await verifyStepUp.call(adminPassword);
      final events = await auditRepo.loadEvents(limit: 10, offset: 0);
      expect(events.any((e) => e.eventTypeKey == 'step_up_granted'), isTrue);
    });

    test('records step_up_denied audit event on wrong password', () async {
      loginAsAdmin();
      await verifyStepUp.call('BadPassword1');
      final events = await auditRepo.loadEvents(limit: 10, offset: 0);
      expect(events.any((e) => e.eventTypeKey == 'step_up_denied'), isTrue);
    });
  });
}
