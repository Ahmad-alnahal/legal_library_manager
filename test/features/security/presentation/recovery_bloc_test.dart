import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/bootstrap_admin_account.dart';
import 'package:legal_library_manager/features/security/application/redeem_recovery_key.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/set_initial_admin_password.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_account_repository.dart';
import 'package:legal_library_manager/features/security/data/repositories/drift_security_audit_repository.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/recovery_bloc.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/recovery_event.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/recovery_state.dart';

class _FixedClock extends Clock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

Future<void> _settle(RecoveryBloc bloc) =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  late AppDatabase db;
  late DriftAccountRepository accountRepo;
  late DriftSecurityAuditRepository auditRepo;
  late SessionManager sessionManager;
  late RecoveryBloc bloc;
  late String recoveryKey;

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

    recoveryKey = await SetInitialAdminPassword(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
    ).call('AdminPass1');

    final redeemUseCase = RedeemRecoveryKey(
      accounts: accountRepo,
      hasher: minimalHasher,
      auditLog: auditRepo,
      clock: clock,
      sessionManager: sessionManager,
    );

    bloc = RecoveryBloc(redeemRecoveryKey: redeemUseCase);
  });

  tearDown(() async {
    bloc.close();
    sessionManager.dispose();
    await db.close();
  });

  group('RecoveryBloc', () {
    test('initial state is RecoveryInitial', () {
      expect(bloc.state, isA<RecoveryInitial>());
    });

    test('valid recovery key emits RecoverySuccess with new key', () async {
      expect(
        bloc.stream,
        emitsInOrder([
          isA<RecoveryInProgress>(),
          isA<RecoverySuccess>(),
        ]),
      );
      bloc.add(RecoverySubmitted(recoveryKey));
      await _settle(bloc);

      final state = bloc.state as RecoverySuccess;
      expect(
        state.newRecoveryKey,
        matches(RegExp(
            r'^[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}$')),
      );
    });

    test('wrong key emits RecoveryError with invalidKey', () async {
      bloc.add(const RecoverySubmitted('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD'));
      await _settle(bloc);
      expect(bloc.state, isA<RecoveryError>());
      expect((bloc.state as RecoveryError).messageKey, 'invalidKey');
    });

    test('throttled attempts emit RecoveryError with throttled', () async {
      for (var i = 0; i < 3; i++) {
        bloc.add(const RecoverySubmitted('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD'));
        await _settle(bloc);
      }
      bloc.add(const RecoverySubmitted('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD'));
      await _settle(bloc);

      final state = bloc.state as RecoveryError;
      expect(state.messageKey, 'throttled');
      expect(state.remainingSeconds, isNotNull);
      expect(state.remainingSeconds, greaterThan(0));
    });

    test('RecoveryErrorDismissed resets to RecoveryInitial', () async {
      bloc.add(const RecoverySubmitted('AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD'));
      await _settle(bloc);
      expect(bloc.state, isA<RecoveryError>());

      bloc.add(const RecoveryErrorDismissed());
      await _settle(bloc);
      expect(bloc.state, isA<RecoveryInitial>());
    });
  });
}
