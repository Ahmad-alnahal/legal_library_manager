import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/create_operator_account.dart';
import 'package:legal_library_manager/features/security/application/issue_temporary_password.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';
import 'package:legal_library_manager/features/security/application/update_operator_account.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_status.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/account_management_bloc.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/account_management_event.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/account_management_state.dart';

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
  late AccountManagementBloc bloc;

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

    // Seed the admin session so _actorId resolves.
    final admin = await accountRepo.findById('admin');
    sessionManager.login(
      Session(
        accountId: 'admin',
        username: admin!.username,
        role: admin.role,
        startedAt: clock.nowUtc(),
      ),
    );
    // Grant step-up so that all use cases pass for this admin session.
    stepUpManager.grant();

    final createOperator = CreateOperatorAccount(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
    final updateOperator = UpdateOperatorAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
    final issueTempPassword = IssueTemporaryPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );

    bloc = AccountManagementBloc(
      accounts: accountRepo,
      createOperator: createOperator,
      updateOperator: updateOperator,
      issueTempPassword: issueTempPassword,
      sessionManager: sessionManager,
    );
  });

  tearDown(() async {
    bloc.close();
    stepUpManager.dispose();
    sessionManager.dispose();
    await db.close();
  });

  group('AccountManagementBloc', () {
    test('initial state is AccountManagementInitial', () {
      expect(bloc.state, isA<AccountManagementInitial>());
    });

    test('load emits Loaded with empty operator list initially', () async {
      expect(
        bloc.stream,
        emitsInOrder([
          isA<AccountManagementLoading>(),
          isA<AccountManagementLoaded>(),
        ]),
      );
      bloc.add(const AccountManagementLoadRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final loaded = bloc.state as AccountManagementLoaded;
      expect(loaded.operators, isEmpty);
      expect(loaded.admin, isNotNull);
      expect(loaded.admin!.internalId, equals('admin'));
    });

    test('create operator emits Loaded with the new operator', () async {
      bloc.add(const AccountManagementLoadRequested());
      await _settle(bloc);

      bloc.add(
        const AccountManagementCreateOperator(
          username: 'op1',
          displayName: 'مشغل أول',
          temporaryPassword: 'TempPass1',
        ),
      );
      await _settle(bloc);

      final loaded = bloc.state as AccountManagementLoaded;
      expect(loaded.operators.length, equals(1));
      expect(loaded.operators.first.username, equals('op1'));
      expect(loaded.operators.first.mustChangePassword, isTrue);
    });

    test('create operator with duplicate username emits Error', () async {
      bloc.add(const AccountManagementLoadRequested());
      await _settle(bloc);

      bloc.add(
        const AccountManagementCreateOperator(
          username: 'op1',
          displayName: 'مشغل أول',
          temporaryPassword: 'TempPass1',
        ),
      );
      await _settle(bloc);

      bloc.add(
        const AccountManagementCreateOperator(
          username: 'op1',
          displayName: 'مشغل ثاني',
          temporaryPassword: 'TempPass2',
        ),
      );
      await _settle(bloc);

      expect(bloc.state, isA<AccountManagementError>());
      expect(
        (bloc.state as AccountManagementError).messageKey,
        equals('duplicateUsername'),
      );
    });

    test(
      'issue temp password emits Loaded with mustChangePassword set',
      () async {
        bloc.add(const AccountManagementLoadRequested());
        await _settle(bloc);

        bloc.add(
          const AccountManagementCreateOperator(
            username: 'op1',
            displayName: 'مشغل',
            temporaryPassword: 'TempPass1',
          ),
        );
        await _settle(bloc);

        // Clear must_change_password by simulating a password change.
        final op = (bloc.state as AccountManagementLoaded).operators.first;
        await accountRepo.updateAccount(op.copyWith(mustChangePassword: false));

        bloc.add(
          AccountManagementIssueTempPassword(
            operatorId: op.internalId,
            temporaryPassword: 'NewTemp1',
          ),
        );
        await _settle(bloc);

        final loaded = bloc.state as AccountManagementLoaded;
        expect(loaded.operators.first.mustChangePassword, isTrue);
      },
    );

    test('suspend operator sets status to suspended', () async {
      bloc.add(const AccountManagementLoadRequested());
      await _settle(bloc);

      bloc.add(
        const AccountManagementCreateOperator(
          username: 'op1',
          displayName: 'مشغل',
          temporaryPassword: 'TempPass1',
        ),
      );
      await _settle(bloc);

      final op = (bloc.state as AccountManagementLoaded).operators.first;
      bloc.add(AccountManagementSuspend(op.internalId));
      await _settle(bloc);

      final loaded = bloc.state as AccountManagementLoaded;
      expect(loaded.operators.first.status, equals(AccountStatus.suspended));
    });

    test('reactivate operator sets status back to active', () async {
      bloc.add(const AccountManagementLoadRequested());
      await _settle(bloc);

      bloc.add(
        const AccountManagementCreateOperator(
          username: 'op1',
          displayName: 'مشغل',
          temporaryPassword: 'TempPass1',
        ),
      );
      await _settle(bloc);

      final op = (bloc.state as AccountManagementLoaded).operators.first;
      bloc.add(AccountManagementSuspend(op.internalId));
      await _settle(bloc);
      bloc.add(AccountManagementReactivate(op.internalId));
      await _settle(bloc);

      final loaded = bloc.state as AccountManagementLoaded;
      expect(loaded.operators.first.status, equals(AccountStatus.active));
    });

    test('ErrorDismissed transitions Error back to Loaded', () async {
      bloc.add(const AccountManagementLoadRequested());
      await _settle(bloc);

      // Trigger an error (duplicate username).
      bloc.add(
        const AccountManagementCreateOperator(
          username: 'op1',
          displayName: 'مشغل',
          temporaryPassword: 'TempPass1',
        ),
      );
      await _settle(bloc);
      bloc.add(
        const AccountManagementCreateOperator(
          username: 'op1',
          displayName: 'مشغل',
          temporaryPassword: 'TempPass2',
        ),
      );
      await _settle(bloc);
      expect(bloc.state, isA<AccountManagementError>());

      bloc.add(const AccountManagementErrorDismissed());
      await _settle(bloc);
      expect(bloc.state, isA<AccountManagementLoaded>());
    });

    test(
      'LogoutRequested calls sessionManager.logout and emits Unauthenticated',
      () async {
        final states = <SessionState>[];
        final sub = sessionManager.sessionStream.listen(states.add);

        bloc.add(const AccountManagementLogoutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(states, contains(isA<Unauthenticated>()));
        expect(sessionManager.currentSession, isNull);

        await sub.cancel();
      },
    );

    test(
      'LogoutRequested does not emit bloc state other than whatever was current',
      () async {
        bloc.add(const AccountManagementLoadRequested());
        await _settle(bloc);

        final statesBefore = bloc.state;
        bloc.add(const AccountManagementLogoutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // The bloc state itself doesn't change — the session stream drives navigation.
        expect(bloc.state, equals(statesBefore));
      },
    );

    test(
      'emits stepUpRequired error when step-up is revoked mid-session',
      () async {
        bloc.add(const AccountManagementLoadRequested());
        await _settle(bloc);

        // Revoke step-up so the next operation fails.
        stepUpManager.revoke();

        bloc.add(
          const AccountManagementCreateOperator(
            username: 'op1',
            displayName: 'مشغل',
            temporaryPassword: 'TempPass1',
          ),
        );
        await _settle(bloc);

        expect(bloc.state, isA<AccountManagementError>());
        expect(
          (bloc.state as AccountManagementError).messageKey,
          equals('stepUpRequired'),
        );
      },
    );
  });
}

Future<void> _settle(AccountManagementBloc bloc) =>
    Future<void>.delayed(const Duration(milliseconds: 200));
