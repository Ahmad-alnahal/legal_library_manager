import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/change_own_password.dart';
import 'package:legal_library_manager/features/security/application/first_login_password_change.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/password_change_bloc.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/password_change_event.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/password_change_state.dart';

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
  late PasswordChangeBloc bloc;

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

    final changeOwnPassword = ChangeOwnPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
    );
    final firstLoginPasswordChange = FirstLoginPasswordChange(
      changeOwnPassword: changeOwnPassword,
      sessionManager: sessionManager,
    );

    bloc = PasswordChangeBloc(
      firstLoginPasswordChange: firstLoginPasswordChange,
    );
  });

  tearDown(() async {
    bloc.close();
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

  group('PasswordChangeBloc', () {
    test('initial state is PasswordChangeInitial', () {
      expect(bloc.state, isA<PasswordChangeInitial>());
    });

    test(
      'emits PasswordChangeError(passwordMismatch) when passwords do not match',
      () async {
        expect(
          bloc.stream,
          emitsInOrder([
            isA<PasswordChangeError>().having(
              (e) => e.messageKey,
              'messageKey',
              'passwordMismatch',
            ),
          ]),
        );
        bloc.add(
          const PasswordChangeSubmitted(
            currentPassword: 'x',
            newPassword: 'NewPass99',
            confirmPassword: 'Different',
          ),
        );
      },
    );

    test('emits [InProgress, Success] on correct credentials', () async {
      loginWithRestrictedSession();
      expect(
        bloc.stream,
        emitsInOrder([
          isA<PasswordChangeInProgress>(),
          isA<PasswordChangeSuccess>(),
        ]),
      );
      bloc.add(
        const PasswordChangeSubmitted(
          currentPassword: 'AdminPass1',
          newPassword: 'NewPass99',
          confirmPassword: 'NewPass99',
        ),
      );
    });

    test(
      'emits [InProgress, Error(incorrectCurrentPassword)] for wrong current password',
      () async {
        loginWithRestrictedSession();
        expect(
          bloc.stream,
          emitsInOrder([
            isA<PasswordChangeInProgress>(),
            isA<PasswordChangeError>().having(
              (e) => e.messageKey,
              'messageKey',
              'incorrectCurrentPassword',
            ),
          ]),
        );
        bloc.add(
          const PasswordChangeSubmitted(
            currentPassword: 'WrongPassword',
            newPassword: 'NewPass99',
            confirmPassword: 'NewPass99',
          ),
        );
      },
    );

    test(
      'emits [InProgress, Error(passwordTooShort)] for weak new password',
      () async {
        loginWithRestrictedSession();
        expect(
          bloc.stream,
          emitsInOrder([
            isA<PasswordChangeInProgress>(),
            isA<PasswordChangeError>().having(
              (e) => e.messageKey,
              'messageKey',
              'passwordTooShort',
            ),
          ]),
        );
        bloc.add(
          const PasswordChangeSubmitted(
            currentPassword: 'AdminPass1',
            newPassword: 'abc',
            confirmPassword: 'abc',
          ),
        );
      },
    );

    test(
      'emits [InProgress, Error(unexpectedError)] when no session is active',
      () async {
        expect(
          bloc.stream,
          emitsInOrder([
            isA<PasswordChangeInProgress>(),
            isA<PasswordChangeError>().having(
              (e) => e.messageKey,
              'messageKey',
              'unexpectedError',
            ),
          ]),
        );
        bloc.add(
          const PasswordChangeSubmitted(
            currentPassword: 'AdminPass1',
            newPassword: 'NewPass99',
            confirmPassword: 'NewPass99',
          ),
        );
      },
    );

    test('PasswordChangeErrorDismissed resets state to PasswordChangeInitial', () async {
      bloc.add(
        const PasswordChangeSubmitted(
          currentPassword: 'x',
          newPassword: 'NewPass99',
          confirmPassword: 'Different',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      bloc.add(const PasswordChangeErrorDismissed());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bloc.state, isA<PasswordChangeInitial>());
    });
  });
}
