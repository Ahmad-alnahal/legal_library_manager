import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/create_operator_account.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart'
    show WeakPasswordException;
import 'package:legal_library_manager/features/security/application/unauthorized_exception.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_status.dart';
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
  late CreateOperatorAccount useCase;

  const minimalHasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 12));

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    sessionManager = SessionManager();

    await BootstrapAdminAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    ).call();

    sessionManager.login(Session(
      accountId: 'admin',
      username: 'marjiy@admin',
      role: AccountRole.admin,
      startedAt: clock.nowUtc(),
    ));

    useCase = CreateOperatorAccount(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
    );
  });

  tearDown(() async {
    sessionManager.dispose();
    await db.close();
  });

  group('CreateOperatorAccount', () {
    test('creates an operator account with the correct fields', () async {
      final id = await useCase.call(
        username: 'op1',
        displayName: 'مشغل أول',
        password: 'TempPass1',
        createdById: 'admin',
      );

      final account = await accountRepo.findById(id);
      expect(account, isNotNull);
      expect(account!.username, equals('op1'));
      expect(account.displayName, equals('مشغل أول'));
      expect(account.role, equals(AccountRole.operator));
      expect(account.status, equals(AccountStatus.active));
      expect(account.mustChangePassword, isTrue);
      expect(account.createdById, equals('admin'));
    });

    test('assigns a unique UUID as internalId', () async {
      final id1 = await useCase.call(
        username: 'op1',
        displayName: 'مشغل أول',
        password: 'TempPass1',
        createdById: 'admin',
      );
      final id2 = await useCase.call(
        username: 'op2',
        displayName: 'مشغل ثاني',
        password: 'TempPass2',
        createdById: 'admin',
      );

      expect(id1, isNot(equals(id2)));
      expect(
          id1,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('password is stored as an Argon2id hash, never plaintext', () async {
      final id = await useCase.call(
        username: 'op1',
        displayName: 'مشغل',
        password: 'TempPass1',
        createdById: 'admin',
      );
      final account = await accountRepo.findById(id);
      expect(account!.passwordHash, startsWith(r'$argon2id'));
      expect(account.passwordHash, isNot(contains('TempPass1')));
    });

    test('operator can log in with the issued temporary password', () async {
      final id = await useCase.call(
        username: 'op1',
        displayName: 'مشغل',
        password: 'TempPass1',
        createdById: 'admin',
      );
      final account = await accountRepo.findById(id);
      final valid =
          await minimalHasher.verify('TempPass1', account!.passwordHash);
      expect(valid, isTrue);
    });

    test('throws DuplicateUsernameException for a duplicate username', () async {
      await useCase.call(
        username: 'op1',
        displayName: 'مشغل أول',
        password: 'TempPass1',
        createdById: 'admin',
      );

      expect(
        () => useCase.call(
          username: 'op1',
          displayName: 'مشغل ثاني',
          password: 'TempPass2',
          createdById: 'admin',
        ),
        throwsA(isA<DuplicateUsernameException>()),
      );
    });

    test('throws DuplicateUsernameException if username matches the admin',
        () async {
      expect(
        () => useCase.call(
          username: 'marjiy@admin',
          displayName: 'مشغل',
          password: 'TempPass1',
          createdById: 'admin',
        ),
        throwsA(isA<DuplicateUsernameException>()),
      );
    });

    test('throws WeakPasswordException for passwords shorter than 8 chars',
        () async {
      expect(
        () => useCase.call(
          username: 'op1',
          displayName: 'مشغل',
          password: 'Short',
          createdById: 'admin',
        ),
        throwsA(isA<WeakPasswordException>()),
      );
    });

    test('records an account_created audit event', () async {
      await useCase.call(
        username: 'op1',
        displayName: 'مشغل',
        password: 'TempPass1',
        createdById: 'admin',
      );
      final events = await auditRepo.loadEvents(limit: 10, offset: 0);
      expect(
        events.any((e) => e.eventTypeKey == 'account_created'),
        isTrue,
      );
    });

    test('listOperators returns only operator accounts', () async {
      await useCase.call(
        username: 'op1',
        displayName: 'مشغل أول',
        password: 'TempPass1',
        createdById: 'admin',
      );
      await useCase.call(
        username: 'op2',
        displayName: 'مشغل ثاني',
        password: 'TempPass2',
        createdById: 'admin',
      );

      final operators = await accountRepo.listOperators();
      expect(operators.length, equals(2));
      expect(operators.every((a) => a.role == AccountRole.operator), isTrue);
      expect(operators.any((a) => a.internalId == 'admin'), isFalse);
    });

    test('operator internalId is immutable across updates', () async {
      final id = await useCase.call(
        username: 'op1',
        displayName: 'مشغل',
        password: 'TempPass1',
        createdById: 'admin',
      );
      final before = await accountRepo.findById(id);
      await accountRepo.updateAccount(
        before!.copyWith(displayName: 'اسم جديد'),
      );
      final after = await accountRepo.findById(id);
      expect(after!.internalId, equals(id));
    });

    test('throws UnauthorizedException when there is no active session',
        () async {
      sessionManager.logout();
      expect(
        () => useCase.call(
          username: 'op1',
          displayName: 'مشغل',
          password: 'TempPass1',
          createdById: 'admin',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws UnauthorizedException when the current session is operator',
        () async {
      final opId = await useCase.call(
        username: 'op1',
        displayName: 'مشغل',
        password: 'TempPass1',
        createdById: 'admin',
      );
      sessionManager.login(Session(
        accountId: opId,
        username: 'op1',
        role: AccountRole.operator,
        startedAt: clock.nowUtc(),
      ));
      expect(
        () => useCase.call(
          username: 'op2',
          displayName: 'مشغل ثاني',
          password: 'TempPass2',
          createdById: opId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
