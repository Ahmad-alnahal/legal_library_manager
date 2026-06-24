// Shared test doubles for security / session dependencies.

import 'dart:async';

import 'package:legal_library_manager/core/di/injection.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

/// A [SessionManager] that never blocks on a timer and always reports a
/// pre-configured session.
///
/// The [sessionStream] emits [Authenticated] with [_adminSession] immediately
/// on first listen and then does nothing further — no inactivity timer fires.
/// This keeps widget tests that navigate to authenticated screens unblocked.
///
/// If [session] is null the stub reports [Unauthenticated] state.
class FakeSessionManager implements SessionManager {
  FakeSessionManager({this._session});

  Session? _session;
  final _controller = StreamController<SessionState>.broadcast();

  static final Session defaultAdminSession = Session(
    accountId: 'admin',
    username: 'marjiy@admin',
    role: AccountRole.admin,
    startedAt: DateTime.utc(2026, 6, 23, 10),
  );

  @override
  Session? get currentSession => _session;

  @override
  SessionState get currentState =>
      _session == null ? const Unauthenticated() : Authenticated(_session!);

  @override
  Stream<SessionState> get sessionStream => _controller.stream;

  @override
  void login(Session session) {
    _session = session;
    _controller.add(Authenticated(session));
  }

  @override
  void logout() {
    _session = null;
    _controller.add(const Unauthenticated());
  }

  @override
  void invalidateAll() {
    _session = null;
    _controller.add(const Unauthenticated());
  }

  @override
  void resetAdminInactivityTimer() {}

  @override
  void dispose() {
    _controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Replaces the registered [SessionManager] with a [FakeSessionManager] that
/// reports an active admin session and never fires an inactivity timer.
///
/// Call after [configureDependencies] in widget tests that pump the full app
/// shell. The lazy singleton is swapped before the [AuthGatePage] first
/// resolves it from DI.
void useStubSessionManager({Session? session}) {
  if (getIt.isRegistered<SessionManager>()) {
    getIt.unregister<SessionManager>();
  }
  getIt.registerLazySingleton<SessionManager>(
    () => FakeSessionManager(
      session: session ?? FakeSessionManager.defaultAdminSession,
    ),
    dispose: (m) => m.dispose(),
  );
}
