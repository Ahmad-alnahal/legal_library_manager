import '../../../../core/time/clock.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';
import 'session_manager.dart';
import 'set_initial_admin_password.dart' show WeakPasswordException;
import 'unauthorized_exception.dart';

/// Thrown when the current password provided does not match the stored hash.
class IncorrectCurrentPasswordException implements Exception {
  const IncorrectCurrentPasswordException();
  @override
  String toString() => 'IncorrectCurrentPasswordException';
}

/// Allows any authenticated user to change their own password.
///
/// Verifies the [currentPassword] against the stored hash before accepting the
/// new one. Clears [mustChangePassword] so the first-login restriction is
/// lifted on success.
///
/// The caller must supply [accountId] matching the current session's own
/// account — operators cannot change another account's password.
class ChangeOwnPassword {
  const ChangeOwnPassword({
    required this._accounts,
    required this._hasher,
    required this._auditLog,
    required this._clock,
    required this._sessionManager,
  });

  final AccountRepository _accounts;
  final PasswordHasher _hasher;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;
  final SessionManager _sessionManager;

  /// Changes the password for [accountId] after verifying [currentPassword].
  ///
  /// Throws [UnauthorizedException] if there is no active session or if
  /// [accountId] does not match the current session's own account.
  /// Throws [WeakPasswordException] if [newPassword] is shorter than 8 chars.
  /// Throws [IncorrectCurrentPasswordException] if [currentPassword] is wrong.
  /// Throws [ArgumentError] if the account is not found.
  Future<void> call({
    required String accountId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.accountId != accountId) {
      throw const UnauthorizedException(
        'Cannot change another account\'s password.',
      );
    }

    if (newPassword.length < 8) {
      throw const WeakPasswordException(
        'Password must be at least 8 characters.',
      );
    }

    final account = await _accounts.findById(accountId);
    if (account == null) throw ArgumentError('Account not found: $accountId');

    final valid = await _hasher.verify(currentPassword, account.passwordHash);
    if (!valid) throw const IncorrectCurrentPasswordException();

    final now = _clock.nowUtc();
    final newHash = await _hasher.hash(newPassword);

    await _accounts.updateAccount(
      account.copyWith(
        passwordHash: newHash,
        mustChangePassword: false,
        updatedAt: now,
      ),
    );

    await _auditLog.insertEvent(
      eventTypeKey: 'password_changed',
      actorAccountId: accountId,
    );
  }
}
