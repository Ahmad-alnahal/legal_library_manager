import 'change_own_password.dart';
import 'session_manager.dart';

/// Orchestrates the first-login password change.
///
/// Delegates credential verification and hashing to [ChangeOwnPassword], then
/// clears the [Session.isRestrictedToPasswordChange] flag by re-registering
/// the updated session with [SessionManager].
///
/// Called from [PasswordChangePage] when the user submits their new password.
class FirstLoginPasswordChange {
  const FirstLoginPasswordChange({
    required this._changeOwnPassword,
    required this._sessionManager,
  });

  final ChangeOwnPassword _changeOwnPassword;
  final SessionManager _sessionManager;

  /// Changes the password for the currently restricted session.
  ///
  /// Re-throws [IncorrectCurrentPasswordException] or [WeakPasswordException]
  /// from [ChangeOwnPassword] on failure.
  ///
  /// Throws [StateError] if there is no active session.
  Future<void> call({
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null) throw StateError('No active session');

    await _changeOwnPassword.call(
      accountId: session.accountId,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    _sessionManager.login(
      session.copyWith(isRestrictedToPasswordChange: false),
    );
  }
}
