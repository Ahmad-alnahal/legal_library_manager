import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/load_audit_log.dart';
import 'package:legal_library_manager/features/security/application/record_failed_login.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/audit_log_bloc.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/audit_log_event.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/audit_log_state.dart';

class _FixedClock extends Clock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

Future<void> _settle(AuditLogBloc bloc) =>
    Future<void>.delayed(const Duration(milliseconds: 100));

final _adminSession = Session(
  accountId: 'admin',
  username: 'marjiy@admin',
  role: AccountRole.admin,
  startedAt: DateTime.utc(2026, 6, 23, 12),
);

void main() {
  late AppDatabase db;
  late DriftAccountRepository accountRepo;
  late DriftSecurityAuditRepository auditRepo;
  late SessionManager sessionManager;
  late LoadAuditLog loadAuditLog;
  late AuditLogBloc bloc;

  final clock = _FixedClock(DateTime.utc(2026, 6, 23, 12));

  setUp(() async {
    db = AppDatabase.inMemory();
    accountRepo = DriftAccountRepository(db);
    auditRepo = DriftSecurityAuditRepository(db);
    sessionManager = SessionManager();
    sessionManager.login(_adminSession);
    loadAuditLog = LoadAuditLog(
      auditLog: auditRepo,
      sessionManager: sessionManager,
    );
    bloc = AuditLogBloc(loadAuditLog: loadAuditLog);
  });

  tearDown(() async {
    bloc.close();
    sessionManager.dispose();
    await db.close();
  });

  group('AuditLogBloc', () {
    test('initial state is AuditLogInitial', () {
      expect(bloc.state, isA<AuditLogInitial>());
    });

    test('AuditLogLoadRequested emits Loading then Loaded', () async {
      expect(
        bloc.stream,
        emitsInOrder([isA<AuditLogLoading>(), isA<AuditLogLoaded>()]),
      );
      bloc.add(const AuditLogLoadRequested());
      await _settle(bloc);
    });

    test('AuditLogLoadRequested emits AuditLogError when not admin', () async {
      sessionManager.logout();
      expect(
        bloc.stream,
        emitsInOrder([isA<AuditLogLoading>(), isA<AuditLogError>()]),
      );
      bloc.add(const AuditLogLoadRequested());
      await _settle(bloc);

      final err = bloc.state as AuditLogError;
      expect(err.messageKey, 'unauthorized');
    });

    test('Loaded state reflects inserted events', () async {
      await BootstrapAdminAccount(
        accounts: accountRepo,
        auditLog: auditRepo,
        clock: clock,
      ).call();

      bloc.add(const AuditLogLoadRequested());
      await _settle(bloc);

      final loaded = bloc.state as AuditLogLoaded;
      expect(loaded.events, isNotEmpty);
      expect(
        loaded.events.any((e) => e.eventTypeKey == 'admin_bootstrapped'),
        isTrue,
      );
    });

    test('hasMore is false when fewer than 25 events returned', () async {
      bloc.add(const AuditLogLoadRequested());
      await _settle(bloc);

      final loaded = bloc.state as AuditLogLoaded;
      expect(loaded.hasMore, isFalse);
    });

    test('hasMore is true when exactly 25 events are loaded', () async {
      final recordFailed = RecordFailedLogin(
        accounts: accountRepo,
        auditLog: auditRepo,
        clock: clock,
      );
      await BootstrapAdminAccount(
        accounts: accountRepo,
        auditLog: auditRepo,
        clock: clock,
      ).call();
      // admin_bootstrapped = 1 event; add 24 more login_failed events = 25 total
      for (var i = 0; i < 24; i++) {
        await recordFailed.call('admin');
      }

      bloc.add(const AuditLogLoadRequested());
      await _settle(bloc);

      final loaded = bloc.state as AuditLogLoaded;
      expect(loaded.events.length, 25);
      expect(loaded.hasMore, isTrue);
    });

    test('AuditLogLoadMoreRequested appends next page', () async {
      await BootstrapAdminAccount(
        accounts: accountRepo,
        auditLog: auditRepo,
        clock: clock,
      ).call();
      final recordFailed = RecordFailedLogin(
        accounts: accountRepo,
        auditLog: auditRepo,
        clock: clock,
      );
      // 27 events total: 1 bootstrap + 25 login_failed + 1 account_auto_suspended
      for (var i = 0; i < 25; i++) {
        await recordFailed.call('admin');
      }

      bloc.add(const AuditLogLoadRequested());
      await _settle(bloc);
      final firstPage = (bloc.state as AuditLogLoaded).events;
      expect(firstPage.length, 25);

      bloc.add(const AuditLogLoadMoreRequested());
      await _settle(bloc);
      final secondPage = (bloc.state as AuditLogLoaded).events;
      expect(secondPage.length, 27);
      expect((bloc.state as AuditLogLoaded).hasMore, isFalse);
    });

    test(
      'AuditLogLoadMoreRequested ignored when not in Loaded state',
      () async {
        bloc.add(const AuditLogLoadMoreRequested());
        await _settle(bloc);
        expect(bloc.state, isA<AuditLogInitial>());
      },
    );

    test('empty repository emits Loaded with empty list', () async {
      bloc.add(const AuditLogLoadRequested());
      await _settle(bloc);

      final loaded = bloc.state as AuditLogLoaded;
      expect(loaded.events, isEmpty);
      expect(loaded.hasMore, isFalse);
    });
  });
}
