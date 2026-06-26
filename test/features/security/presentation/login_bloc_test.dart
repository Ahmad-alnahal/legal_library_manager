import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/authenticate_user.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/record_failed_login.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_status.dart';
import 'package:legal_library_manager/features/security/domain/entities/failed_login_state.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/login_bloc.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/login_event.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/login_state.dart';

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
  late LoginBloc bloc;

  const hasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 10));

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    sessionManager = SessionManager();

    final auth = AuthenticateUser(
      accounts: accountRepo,
      hasher: hasher,
      sessionManager: sessionManager,
      auditLog: auditRepo,
      clock: clock,
      recordFailedLogin: RecordFailedLogin(
        accounts: accountRepo,
        auditLog: auditRepo,
        clock: clock,
      ),
    );

    bloc = LoginBloc(authenticateUser: auth);

    await BootstrapAdminAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    ).call();

    await SetInitialAdminPassword(
      accounts: accountRepo,
      hasher: hasher,
      auditLog: auditRepo,
      clock: clock,
    ).call('AdminPass1');
  });

  tearDown(() async {
    bloc.close();
    sessionManager.dispose();
    await db.close();
  });

  group('LoginBloc', () {
    test('initial state is LoginInitial', () {
      expect(bloc.state, isA<LoginInitial>());
    });

    test(
      'emits LoginInProgress then LoginSuccess on correct credentials',
      () async {
        expect(
          bloc.stream,
          emitsInOrder([isA<LoginInProgress>(), isA<LoginSuccess>()]),
        );
        bloc.add(
          const LoginSubmitted(
            username: 'marjiy@admin',
            password: 'AdminPass1',
          ),
        );
      },
    );

    test('LoginSuccess carries the session', () async {
      final states = <LoginState>[];
      bloc.stream.listen(states.add);
      bloc.add(
        const LoginSubmitted(username: 'marjiy@admin', password: 'AdminPass1'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final success = states.whereType<LoginSuccess>().firstOrNull;
      expect(success, isNotNull);
      expect(success!.session.accountId, 'admin');
    });

    test(
      'emits LoginInProgress then LoginInvalidCredentials on wrong password',
      () async {
        expect(
          bloc.stream,
          emitsInOrder([
            isA<LoginInProgress>(),
            isA<LoginInvalidCredentials>(),
          ]),
        );
        bloc.add(
          const LoginSubmitted(
            username: 'marjiy@admin',
            password: 'WrongPassword',
          ),
        );
      },
    );

    test('emits LoginAccountSuspended when account is suspended', () async {
      final admin = await accountRepo.findById('admin');
      await accountRepo.updateAccount(
        admin!.copyWith(status: AccountStatus.suspended),
      );

      expect(
        bloc.stream,
        emitsInOrder([isA<LoginInProgress>(), isA<LoginAccountSuspended>()]),
      );
      bloc.add(
        const LoginSubmitted(username: 'marjiy@admin', password: 'AdminPass1'),
      );
    });

    test('emits LoginDelayed when delay is active', () async {
      final futureUnlock = clock.nowUtc().add(const Duration(seconds: 60));
      await accountRepo.upsertSecurityState(
        'admin',
        FailedLoginState(consecutiveFailures: 1, unlockNotBefore: futureUnlock),
      );

      expect(
        bloc.stream,
        emitsInOrder([isA<LoginInProgress>(), isA<LoginDelayed>()]),
      );
      bloc.add(
        const LoginSubmitted(username: 'marjiy@admin', password: 'AdminPass1'),
      );
    });

    test('LoginErrorDismissed resets state to LoginInitial', () async {
      bloc.add(
        const LoginSubmitted(
          username: 'marjiy@admin',
          password: 'WrongPassword',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      bloc.add(const LoginErrorDismissed());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bloc.state, isA<LoginInitial>());
    });
  });
}
