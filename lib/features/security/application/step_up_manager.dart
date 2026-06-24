// lib/features/security/application/step_up_manager.dart

import 'dart:async';

/// Holds a short-lived step-up authentication approval for the current admin
/// session.
///
/// Step-up approval is granted by [VerifyAdminStepUp] after the admin re-enters
/// their password. Approval expires automatically after [_stepUpWindow] and is
/// revoked immediately on any session-ending event (logout, inactivity expiry,
/// or recovery key redemption).
///
/// Like [SessionManager], this class is in-memory only. Nothing is written to
/// disk, the registry, or any persistent store.
///
/// For testability the window is injectable; pass a short [Duration] in tests
/// so they do not wait five minutes.
class StepUpManager {
  StepUpManager({this._stepUpWindow = const Duration(minutes: 5)});

  final Duration _stepUpWindow;
  bool _isApproved = false;
  Timer? _expiryTimer;

  /// True when a fresh step-up approval is currently active.
  bool get isApproved => _isApproved;

  /// Grants step-up approval for [_stepUpWindow] starting now.
  ///
  /// Cancels and restarts the expiry timer if approval was already active.
  void grant() {
    _expiryTimer?.cancel();
    _isApproved = true;
    _expiryTimer = Timer(_stepUpWindow, revoke);
  }

  /// Immediately revokes any active step-up approval and cancels the expiry
  /// timer.
  void revoke() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _isApproved = false;
  }

  /// Releases resources. Call when the app is shutting down.
  void dispose() {
    revoke();
  }
}
