import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

Session _adminSession({
  DateTime? startedAt,
  bool restrictedToPasswordChange = false,
}) =>
    Session(
      accountId: 'admin',
      username: 'marjiy@admin',
      role: AccountRole.admin,
      startedAt: startedAt ?? DateTime.utc(2026, 6, 23, 10),
      isRestrictedToPasswordChange: restrictedToPasswordChange,
    );

Session _operatorSession() => Session(
      accountId: 'op_1',
      username: 'operator1',
      role: AccountRole.operator,
      startedAt: DateTime.utc(2026, 6, 23, 10),
    );

void main() {
  late SessionManager manager;

  setUp(() {
    manager = SessionManager(adminTimeout: const Duration(milliseconds: 200));
  });

  tearDown(() => manager.dispose());

  group('initial state', () {
    test('currentSession is null', () {
      expect(manager.currentSession, isNull);
    });

    test('currentState is Unauthenticated', () {
      expect(manager.currentState, isA<Unauthenticated>());
    });
  });

  group('login', () {
    test('sets currentSession', () {
      final session = _adminSession();
      manager.login(session);
      expect(manager.currentSession, equals(session));
    });

    test('emits Authenticated state', () async {
      final session = _adminSession();
      expect(
        manager.sessionStream,
        emits(isA<Authenticated>()),
      );
      manager.login(session);
    });

    test('currentState is Authenticated after login', () {
      final session = _adminSession();
      manager.login(session);
      expect(manager.currentState, isA<Authenticated>());
    });
  });

  group('logout', () {
    test('clears currentSession', () {
      manager.login(_adminSession());
      manager.logout();
      expect(manager.currentSession, isNull);
    });

    test('emits Unauthenticated state', () async {
      manager.login(_adminSession());
      expect(
        manager.sessionStream,
        emits(isA<Unauthenticated>()),
      );
      manager.logout();
    });
  });

  group('invalidateAll', () {
    test('clears currentSession', () {
      manager.login(_adminSession());
      manager.invalidateAll();
      expect(manager.currentSession, isNull);
    });

    test('emits Unauthenticated state', () async {
      manager.login(_adminSession());
      expect(
        manager.sessionStream,
        emits(isA<Unauthenticated>()),
      );
      manager.invalidateAll();
    });
  });

  group('admin inactivity timer', () {
    test('emits AdminSessionExpired after timeout', () async {
      final states = <SessionState>[];
      final sub = manager.sessionStream.listen(states.add);

      manager.login(_adminSession());
      // Wait for the 200ms test timeout to fire.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(states, contains(isA<AdminSessionExpired>()));
      await sub.cancel();
    });

    test('resetAdminInactivityTimer restarts the countdown', () async {
      final states = <SessionState>[];
      final sub = manager.sessionStream.listen(states.add);

      manager.login(_adminSession());
      // Reset at ~100ms — timer should NOT have fired yet.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      manager.resetAdminInactivityTimer();
      // At ~200ms total (100ms since reset) the timer should still be running.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(states, isNot(contains(isA<AdminSessionExpired>())));

      // After another 150ms (250ms since reset), the timer fires.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(states, contains(isA<AdminSessionExpired>()));

      await sub.cancel();
    });

    test('operator session does not start inactivity timer', () async {
      final states = <SessionState>[];
      final sub = manager.sessionStream.listen(states.add);

      manager.login(_operatorSession());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(states, isNot(contains(isA<AdminSessionExpired>())));
      await sub.cancel();
    });

    test('resetAdminInactivityTimer is no-op for operator session', () {
      manager.login(_operatorSession());
      // Should not throw even if called on an operator session.
      expect(() => manager.resetAdminInactivityTimer(), returnsNormally);
    });

    test('session is null after timer fires', () async {
      manager.login(_adminSession());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(manager.currentSession, isNull);
    });
  });

  // These tests document and verify the behavior that the AppShellPage
  // Listener hook relies on: repeated calls to resetAdminInactivityTimer()
  // (once per pointer/scroll event) keep the admin session alive as long as
  // the admin is actively using the app.
  group('repeated-activity pattern (AppShellPage Listener contract)', () {
    test('continuous activity beyond one timeout window keeps session alive',
        () async {
      manager.login(_adminSession());

      // Simulate pointer-down events at 60 ms intervals (6 events = 360 ms
      // total — well past the 200 ms timeout, but the timer is reset each
      // time so the session should remain active throughout).
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        manager.resetAdminInactivityTimer();
      }

      expect(manager.currentSession, isNotNull,
          reason: 'Session must survive repeated resets');
    });

    test('session expires after activity stops', () async {
      final states = <SessionState>[];
      final sub = manager.sessionStream.listen(states.add);

      manager.login(_adminSession());

      // Stay active for 150 ms then go idle.
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        manager.resetAdminInactivityTimer();
      }

      expect(manager.currentSession, isNotNull);

      // No more resets — wait for the 200 ms timeout to fire.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(manager.currentSession, isNull);
      expect(states, contains(isA<AdminSessionExpired>()));

      await sub.cancel();
    });

    test('each reset independently delays expiry', () async {
      // Verify that each reset starts a fresh countdown rather than extending
      // an existing one.
      manager.login(_adminSession());

      // First reset at 50 ms.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      manager.resetAdminInactivityTimer();

      // Second reset at 100 ms (50 ms after first).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      manager.resetAdminInactivityTimer();

      // At 200 ms after the second reset the timer fires.
      // At 150 ms since the last reset the session should still be active.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(manager.currentSession, isNotNull);

      // After a full 200 ms since the last reset it should have expired.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(manager.currentSession, isNull);
    });
  });
}
