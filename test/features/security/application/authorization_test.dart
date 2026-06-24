import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/change_own_password.dart';
import 'package:legal_library_manager/features/security/application/create_operator_account.dart';
import 'package:legal_library_manager/features/security/application/issue_temporary_password.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';
import 'package:legal_library_manager/features/security/application/step_up_required_exception.dart';
import 'package:legal_library_manager/features/security/application/unauthorized_exception.dart';
import 'package:legal_library_manager/features/security/application/update_operator_account.dart';
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
  late CreateOperatorAccount createOperator;
  late UpdateOperatorAccount updateOperator;
  late IssueTemporaryPassword issueTempPassword;
  late ChangeOwnPassword changeOwnPassword;

  const minimalHasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 12));

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
    ).call('AdminPass1');

    createOperator = CreateOperatorAccount(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
    updateOperator = UpdateOperatorAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
    issueTempPassword = IssueTemporaryPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
    changeOwnPassword = ChangeOwnPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
    );
  });

  tearDown(() async {
    stepUpManager.dispose();
    sessionManager.dispose();
    await db.close();
  });

  void loginAsAdmin() {
    sessionManager.login(Session(
      accountId: 'admin',
      username: 'marjiy@admin',
      role: AccountRole.admin,
      startedAt: clock.nowUtc(),
    ));
  }

  /// Creates a test operator; uses admin session + step-up approval.
  Future<String> createTestOperator() async {
    loginAsAdmin();
    stepUpManager.grant();
    final id = await createOperator.call(
      username: 'op1',
      displayName: 'مشغل',
      password: 'TempPass1',
      createdById: 'admin',
    );
    return id;
  }

  group('CreateOperatorAccount — authorization', () {
    test('throws UnauthorizedException when no session', () {
      expect(
        () => createOperator.call(
          username: 'op1',
          displayName: 'مشغل',
          password: 'TempPass1',
          createdById: 'admin',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws UnauthorizedException when operator session', () async {
      final opId = await createTestOperator();
      sessionManager.login(Session(
        accountId: opId,
        username: 'op1',
        role: AccountRole.operator,
        startedAt: clock.nowUtc(),
      ));
      expect(
        () => createOperator.call(
          username: 'op2',
          displayName: 'مشغل ثاني',
          password: 'TempPass2',
          createdById: opId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws StepUpRequiredException when admin but no step-up', () {
      loginAsAdmin();
      // Step-up NOT granted.
      expect(
        () => createOperator.call(
          username: 'op1',
          displayName: 'مشغل',
          password: 'TempPass1',
          createdById: 'admin',
        ),
        throwsA(isA<StepUpRequiredException>()),
      );
    });

    test('succeeds with admin session and step-up granted', () async {
      loginAsAdmin();
      stepUpManager.grant();
      final id = await createOperator.call(
        username: 'op1',
        displayName: 'مشغل',
        password: 'TempPass1',
        createdById: 'admin',
      );
      expect(id, isNotEmpty);
    });
  });

  group('UpdateOperatorAccount — authorization', () {
    test('throws UnauthorizedException when no session', () async {
      final opId = await createTestOperator();
      sessionManager.logout();
      expect(
        () => updateOperator.call(
          operatorId: opId,
          displayName: 'اسم جديد',
          actorAccountId: 'admin',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws UnauthorizedException when operator session', () async {
      final opId = await createTestOperator();
      sessionManager.login(Session(
        accountId: opId,
        username: 'op1',
        role: AccountRole.operator,
        startedAt: clock.nowUtc(),
      ));
      expect(
        () => updateOperator.call(
          operatorId: opId,
          displayName: 'اسم جديد',
          actorAccountId: opId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws StepUpRequiredException when admin but no step-up', () async {
      final opId = await createTestOperator();
      loginAsAdmin();
      // Step-up revoked after createTestOperator cleared state on re-login.
      stepUpManager.revoke();
      expect(
        () => updateOperator.call(
          operatorId: opId,
          displayName: 'اسم جديد',
          actorAccountId: 'admin',
        ),
        throwsA(isA<StepUpRequiredException>()),
      );
    });

    test('succeeds with admin session and step-up granted', () async {
      final opId = await createTestOperator();
      loginAsAdmin();
      stepUpManager.grant();
      await expectLater(
        updateOperator.call(
          operatorId: opId,
          displayName: 'اسم محدث',
          actorAccountId: 'admin',
        ),
        completes,
      );
    });
  });

  group('IssueTemporaryPassword — authorization', () {
    test('throws UnauthorizedException when no session', () async {
      final opId = await createTestOperator();
      sessionManager.logout();
      expect(
        () => issueTempPassword.call(
          operatorId: opId,
          temporaryPassword: 'NewTemp1',
          actorAccountId: 'admin',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws UnauthorizedException when operator session', () async {
      final opId = await createTestOperator();
      sessionManager.login(Session(
        accountId: opId,
        username: 'op1',
        role: AccountRole.operator,
        startedAt: clock.nowUtc(),
      ));
      expect(
        () => issueTempPassword.call(
          operatorId: opId,
          temporaryPassword: 'NewTemp1',
          actorAccountId: opId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws StepUpRequiredException when admin but no step-up', () async {
      final opId = await createTestOperator();
      loginAsAdmin();
      stepUpManager.revoke();
      expect(
        () => issueTempPassword.call(
          operatorId: opId,
          temporaryPassword: 'NewTemp1',
          actorAccountId: 'admin',
        ),
        throwsA(isA<StepUpRequiredException>()),
      );
    });

    test('succeeds with admin session and step-up granted', () async {
      final opId = await createTestOperator();
      loginAsAdmin();
      stepUpManager.grant();
      await expectLater(
        issueTempPassword.call(
          operatorId: opId,
          temporaryPassword: 'NewTemp1',
          actorAccountId: 'admin',
        ),
        completes,
      );
    });
  });

  group('ChangeOwnPassword — does not require step-up', () {
    test('throws UnauthorizedException when no session', () {
      expect(
        () => changeOwnPassword.call(
          accountId: 'admin',
          currentPassword: 'AdminPass1',
          newPassword: 'NewPass99',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws UnauthorizedException when trying to change another account',
        () async {
      final opId = await createTestOperator();
      loginAsAdmin();
      expect(
        () => changeOwnPassword.call(
          accountId: opId,
          currentPassword: 'TempPass1',
          newPassword: 'NewPass99',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('succeeds with active session — no step-up required', () async {
      loginAsAdmin();
      await expectLater(
        changeOwnPassword.call(
          accountId: 'admin',
          currentPassword: 'AdminPass1',
          newPassword: 'NewAdminPass1',
        ),
        completes,
      );
    });
  });
}
