import 'dart:async';

import '../domain/entities/account_role.dart';
import '../domain/entities/session.dart';

/// The possible states of the session stream emitted by [SessionManager].
sealed class SessionState {
  const SessionState();
}

/// No active session — login is required.
final class Unauthenticated extends SessionState {
  const Unauthenticated();
}

/// A session is active.
final class Authenticated extends SessionState {
  const Authenticated(this.session);
  final Session session;
}

/// The administrator session expired due to 30 minutes of inactivity.
///
/// Callers should save any pending draft state before redirecting to login.
final class AdminSessionExpired extends SessionState {
  const AdminSessionExpired();
}

/// Singleton in-memory session holder and admin inactivity guard.
///
/// Sessions are guaranteed in-memory only — they are never written to disk,
/// a registry, or any persistent store. Every app restart begins unauthenticated.
///
/// For testability the admin inactivity timeout is injectable:
/// pass a short [adminTimeout] in tests so they do not wait 30 minutes.
class SessionManager {
  SessionManager({this._adminTimeout = const Duration(minutes: 30)});

  final Duration _adminTimeout;

  Session? _currentSession;
  Timer? _inactivityTimer;

  final _controller = StreamController<SessionState>.broadcast();

  /// The currently active session, or null when unauthenticated.
  Session? get currentSession => _currentSession;

  /// Stream of session state changes.
  ///
  /// Starts at [Unauthenticated]. Emits [Authenticated] on login,
  /// [Unauthenticated] on logout, and [AdminSessionExpired] when the admin
  /// inactivity timer fires.
  Stream<SessionState> get sessionStream => _controller.stream;

  /// The current state as a one-shot value (does not replay on listen).
  SessionState get currentState =>
      _currentSession == null ? const Unauthenticated() : Authenticated(_currentSession!);

  /// Starts a new session.
  ///
  /// Cancels any previous inactivity timer. Starts a fresh admin inactivity
  /// timer when [session.role] is [AccountRole.admin].
  void login(Session session) {
    _cancelTimer();
    _currentSession = session;
    _controller.add(Authenticated(session));
    if (session.role == AccountRole.admin) {
      _startTimer();
    }
  }

  /// Ends the current session.
  void logout() {
    _cancelTimer();
    _currentSession = null;
    _controller.add(const Unauthenticated());
  }

  /// Clears all sessions — used by recovery key redemption to invalidate any
  /// active session before the admin resets their password.
  void invalidateAll() {
    _cancelTimer();
    _currentSession = null;
    _controller.add(const Unauthenticated());
  }

  /// Resets the admin inactivity timer.
  ///
  /// Call this on any meaningful user interaction so the 30-minute window
  /// restarts. No-op when there is no active admin session.
  void resetAdminInactivityTimer() {
    if (_currentSession?.role != AccountRole.admin) return;
    _cancelTimer();
    _startTimer();
  }

  void _startTimer() {
    _inactivityTimer = Timer(_adminTimeout, _onAdminInactivityExpired);
  }

  void _cancelTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void _onAdminInactivityExpired() {
    _currentSession = null;
    _controller.add(const AdminSessionExpired());
  }

  /// Releases resources. Call when the app is shutting down.
  void dispose() {
    _cancelTimer();
    _controller.close();
  }
}
