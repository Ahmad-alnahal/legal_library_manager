import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/change_own_password.dart';
import 'package:legal_library_manager/features/security/application/first_login_password_change.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart'
    show SetInitialAdminPassword, WeakPasswordException;
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';
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
  late ChangeOwnPassword changeOwnPassword;
  late FirstLoginPasswordChange firstLoginPasswordChange;

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

    changeOwnPassword = ChangeOwnPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
    );
    firstLoginPasswordChange = FirstLoginPasswordChange(
      changeOwnPassword: changeOwnPassword,
      sessionManager: sessionManager,
    );
  });

  tearDown(() async {
    stepUpManager.dispose();
    sessionManager.dispose();
    await db.close();
  });

  void loginWithRestrictedSession() {
    sessionManager.login(
      Session(
        accountId: 'admin',
        username: 'marjiy@admin',
        role: AccountRole.admin,
        startedAt: clock.nowUtc(),
        isRestrictedToPasswordChange: true,
      ),
    );
  }

  group('FirstLoginPasswordChange', () {
    test('throws StateError when no active session', () {
      expect(
        () => firstLoginPasswordChange.call(
          currentPassword: 'AdminPass1',
          newPassword: 'NewPass99',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'succeeds and clears restriction with correct credentials',
      () async {
        loginWithRestrictedSession();
        await expectLater(
          firstLoginPasswordChange.call(
            currentPassword: 'AdminPass1',
            newPassword: 'NewPass99',
          ),
          completes,
        );
        expect(
          sessionManager.currentSession!.isRestrictedToPasswordChange,
          isFalse,
        );
      },
    );

    test(
      'throws IncorrectCurrentPasswordException for wrong current password',
      () async {
        loginWithRestrictedSession();
        expect(
          () => firstLoginPasswordChange.call(
            currentPassword: 'WrongPassword',
            newPassword: 'NewPass99',
          ),
          throwsA(isA<IncorrectCurrentPasswordException>()),
        );
      },
    );

    test(
      'throws WeakPasswordException for new password shorter than 8 chars',
      () async {
        loginWithRestrictedSession();
        expect(
          () => firstLoginPasswordChange.call(
            currentPassword: 'AdminPass1',
            newPassword: 'short',
          ),
          throwsA(isA<WeakPasswordException>()),
        );
      },
    );
  });
}
