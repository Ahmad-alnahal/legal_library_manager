import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/record_failed_login.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
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
  late RecordFailedLogin useCase;

  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 12));

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    useCase = RecordFailedLogin(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    );

    await BootstrapAdminAccount(
      accounts: accountRepo,
      auditLog: auditRepo,
      clock: clock,
    ).call();
  });

  tearDown(() async => db.close());

  group('RecordFailedLogin', () {
    test('first failure sets 10-second delay', () async {
      await useCase.call('admin');
      final state = await accountRepo.getSecurityState('admin');
      expect(state!.consecutiveFailures, 1);
      expect(state.unlockNotBefore, isNotNull);
      final expectedUnlock = clock.nowUtc().add(
        Duration(seconds: kLoginDelaySchedule[1]!),
      );
      expect(
        state.unlockNotBefore!.difference(expectedUnlock).abs().inMilliseconds,
        lessThan(1000),
      );
    });

    test('second failure sets 30-second delay', () async {
      await useCase.call('admin');
      await useCase.call('admin');
      final state = await accountRepo.getSecurityState('admin');
      expect(state!.consecutiveFailures, 2);
      final expectedUnlock = clock.nowUtc().add(
        Duration(seconds: kLoginDelaySchedule[2]!),
      );
      expect(
        state.unlockNotBefore!.difference(expectedUnlock).abs().inMilliseconds,
        lessThan(1000),
      );
    });

    test('third failure sets 60-second delay', () async {
      await useCase.call('admin');
      await useCase.call('admin');
      await useCase.call('admin');
      final state = await accountRepo.getSecurityState('admin');
      expect(state!.consecutiveFailures, 3);
      final expectedUnlock = clock.nowUtc().add(
        Duration(seconds: kLoginDelaySchedule[3]!),
      );
      expect(
        state.unlockNotBefore!.difference(expectedUnlock).abs().inMilliseconds,
        lessThan(1000),
      );
    });

    test('$kAutoSuspendAfter consecutive failures auto-suspends the account',
        () async {
      for (var i = 0; i < kAutoSuspendAfter; i++) {
        await useCase.call('admin');
      }
      final account = await accountRepo.findById('admin');
      expect(account!.status, AccountStatus.suspended);
    });

    test('suspension is recorded only once even with further failures',
        () async {
      for (var i = 0; i < kAutoSuspendAfter + 2; i++) {
        await useCase.call('admin');
      }
      final account = await accountRepo.findById('admin');
      expect(account!.status, AccountStatus.suspended);
      final events = await auditRepo.loadEvents(limit: 50, offset: 0);
      expect(
        events.where((e) => e.eventTypeKey == 'account_auto_suspended').length,
        1,
      );
    });

    test('records a login_failed audit event on every call', () async {
      await useCase.call('admin');
      await useCase.call('admin');
      final events = await auditRepo.loadEvents(limit: 20, offset: 0);
      expect(
        events.where((e) => e.eventTypeKey == 'login_failed').length,
        2,
      );
    });

    test('records account_auto_suspended audit event on suspension', () async {
      for (var i = 0; i < kAutoSuspendAfter; i++) {
        await useCase.call('admin');
      }
      final events = await auditRepo.loadEvents(limit: 20, offset: 0);
      expect(
        events.any((e) => e.eventTypeKey == 'account_auto_suspended'),
        isTrue,
      );
    });

    test('preserves recoveryAttemptCount across login failures', () async {
      await accountRepo.upsertSecurityState(
        'admin',
        const FailedLoginState(
          consecutiveFailures: 0,
          recoveryAttemptCount: 2,
        ),
      );
      await useCase.call('admin');
      final state = await accountRepo.getSecurityState('admin');
      expect(state!.recoveryAttemptCount, 2);
    });
  });
}
