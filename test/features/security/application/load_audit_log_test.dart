import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/load_audit_log.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/unauthorized_exception.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
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
  late LoadAuditLog useCase;

  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 12));

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    sessionManager = SessionManager();
    useCase = LoadAuditLog(
      auditLog: auditRepo,
      sessionManager: sessionManager,
    );

    await BootstrapAdminAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    ).call();
  });

  tearDown(() async {
    sessionManager.dispose();
    await db.close();
  });

  group('LoadAuditLog', () {
    test('throws UnauthorizedException when no session', () async {
      await expectLater(
        useCase(limit: 25, offset: 0),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws UnauthorizedException for operator session', () async {
      sessionManager.login(Session(
        accountId: 'op_1',
        username: 'operator1',
        role: AccountRole.operator,
        startedAt: clock.nowUtc(),
      ));
      await expectLater(
        useCase(limit: 25, offset: 0),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('returns events for admin session', () async {
      sessionManager.login(Session(
        accountId: 'admin',
        username: 'marjiy@admin',
        role: AccountRole.admin,
        startedAt: clock.nowUtc(),
      ));
      final events = await useCase(limit: 25, offset: 0);
      expect(events, isNotEmpty);
      expect(events.first.eventTypeKey, 'admin_bootstrapped');
    });

    test('respects limit and offset for admin session', () async {
      sessionManager.login(Session(
        accountId: 'admin',
        username: 'marjiy@admin',
        role: AccountRole.admin,
        startedAt: clock.nowUtc(),
      ));
      // Insert an additional event.
      await auditRepo.insertEvent(eventTypeKey: 'login_success', actorAccountId: 'admin');

      final page1 = await useCase(limit: 1, offset: 0);
      final page2 = await useCase(limit: 1, offset: 1);
      expect(page1.length, 1);
      expect(page2.length, 1);
      expect(page1.first.id, isNot(equals(page2.first.id)));
    });
  });
}
