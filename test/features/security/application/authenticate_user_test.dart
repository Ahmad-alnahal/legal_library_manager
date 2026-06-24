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
  late AuthenticateUser useCase;

  // Minimal Argon2id params to keep tests fast.
  const hasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
  final fixedNow = DateTime.utc(2026, 6, 23, 10);
  final clock = _FixedClock(fixedNow);

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    sessionManager = SessionManager();

    useCase = AuthenticateUser(
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

    // Bootstrap admin + set a known password so tests can authenticate.
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
    sessionManager.dispose();
    await db.close();
  });

  group('AuthenticateUser', () {
    test('correct credentials create a session', () async {
      final result = await useCase(
        username: 'marjiy@admin',
        password: 'AdminPass1',
      );
      expect(result, isA<AuthSuccess>());
      expect(sessionManager.currentSession, isNotNull);
    });

    test('correct credentials return session with admin role', () async {
      final result =
          await useCase(username: 'marjiy@admin', password: 'AdminPass1')
              as AuthSuccess;
      expect(result.session.role.name, 'admin');
      expect(result.session.accountId, 'admin');
    });

    test('wrong password returns AuthInvalidCredentials', () async {
      final result =
          await useCase(username: 'marjiy@admin', password: 'WrongPass');
      expect(result, isA<AuthInvalidCredentials>());
      expect(sessionManager.currentSession, isNull);
    });

    test('unknown username returns AuthInvalidCredentials', () async {
      final result = await useCase(username: 'nobody', password: 'AnyPass');
      expect(result, isA<AuthInvalidCredentials>());
    });

    test('suspended account returns AuthAccountSuspended without checking password',
        () async {
      final admin = await accountRepo.findById('admin');
      await accountRepo.updateAccount(
        admin!.copyWith(status: AccountStatus.suspended),
      );
      final result =
          await useCase(username: 'marjiy@admin', password: 'AdminPass1');
      expect(result, isA<AuthAccountSuspended>());
      expect(sessionManager.currentSession, isNull);
    });

    test('active delay returns AuthLoginDelayed with remaining seconds',
        () async {
      final futureUnlock =
          fixedNow.add(const Duration(seconds: 30));
      await accountRepo.upsertSecurityState(
        'admin',
        FailedLoginState(
          consecutiveFailures: 1,
          unlockNotBefore: futureUnlock,
        ),
      );
      final result =
          await useCase(username: 'marjiy@admin', password: 'AdminPass1');
      expect(result, isA<AuthLoginDelayed>());
      final delayed = result as AuthLoginDelayed;
      expect(delayed.remainingSeconds, greaterThan(0));
      expect(delayed.remainingSeconds, lessThanOrEqualTo(30));
      expect(sessionManager.currentSession, isNull);
    });

    test('expired delay does not block login', () async {
      final pastUnlock =
          fixedNow.subtract(const Duration(seconds: 1));
      await accountRepo.upsertSecurityState(
        'admin',
        FailedLoginState(
          consecutiveFailures: 1,
          unlockNotBefore: pastUnlock,
        ),
      );
      final result =
          await useCase(username: 'marjiy@admin', password: 'AdminPass1');
      expect(result, isA<AuthSuccess>());
    });

    test('successful login resets security state', () async {
      await accountRepo.upsertSecurityState(
        'admin',
        const FailedLoginState(consecutiveFailures: 2),
      );
      await useCase(username: 'marjiy@admin', password: 'AdminPass1');
      final state = await accountRepo.getSecurityState('admin');
      expect(state?.consecutiveFailures, 0);
    });

    test('successful login records login_success audit event', () async {
      await useCase(username: 'marjiy@admin', password: 'AdminPass1');
      final events = await auditRepo.loadEvents(limit: 20, offset: 0);
      expect(
        events.any((e) => e.eventTypeKey == 'login_success'),
        isTrue,
      );
    });

    test('mustChangePassword on account sets isRestrictedToPasswordChange',
        () async {
      // Bootstrap creates admin with mustChangePassword=true then
      // SetInitialAdminPassword sets it to false. Re-set it to true.
      final admin = await accountRepo.findById('admin');
      await accountRepo.updateAccount(
        admin!.copyWith(mustChangePassword: true),
      );
      final result =
          await useCase(username: 'marjiy@admin', password: 'AdminPass1')
              as AuthSuccess;
      expect(result.session.isRestrictedToPasswordChange, isTrue);
    });
  });
}
