import 'dart:math';

import '../../../../core/time/clock.dart';
import '../domain/entities/account.dart';
import '../domain/entities/account_role.dart';
import '../domain/entities/account_status.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';
import 'session_manager.dart';
import 'set_initial_admin_password.dart' show WeakPasswordException;
import 'step_up_manager.dart';
import 'step_up_required_exception.dart';
import 'unauthorized_exception.dart';

/// Thrown when the requested username is already taken by another account.
class DuplicateUsernameException implements Exception {
  const DuplicateUsernameException(this.username);
  final String username;
  @override
  String toString() =>
      'DuplicateUsernameException: "$username" is already taken';
}

class CreateOperatorAccount {
  const CreateOperatorAccount({
    required this._accounts,
    required this._hasher,
    required this._auditLog,
    required this._clock,
    required this._sessionManager,
    required this._stepUpManager,
  });

  final AccountRepository _accounts;
  final PasswordHasher _hasher;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;
  final SessionManager _sessionManager;
  final StepUpManager _stepUpManager;

  /// Creates a new operator account with [username], [displayName], and a
  /// temporary [password].
  ///
  /// The account is created with [mustChangePassword] = true, forcing a
  /// password change on first login. Returns the new account's [internalId]
  /// (UUID v4).
  ///
  /// Throws [UnauthorizedException] if the current session is not admin.
  /// Throws [StepUpRequiredException] if no fresh step-up approval exists.
  /// Throws [DuplicateUsernameException] if [username] is already taken.
  /// Throws [WeakPasswordException] if [password] is shorter than 8 chars.
  Future<String> call({
    required String username,
    required String displayName,
    required String password,
    required String createdById,
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      throw const UnauthorizedException('Admin role required.');
    }
    if (!_stepUpManager.isApproved) {
      throw const StepUpRequiredException();
    }

    if (password.length < 8) {
      throw const WeakPasswordException(
        'Password must be at least 8 characters.',
      );
    }

    final existing = await _accounts.findByUsername(username);
    if (existing != null) throw DuplicateUsernameException(username);

    final now = _clock.nowUtc();
    final internalId = _generateUuid();
    final passwordHash = await _hasher.hash(password);

    await _accounts.insertAccount(
      Account(
        internalId: internalId,
        username: username,
        displayName: displayName,
        role: AccountRole.operator,
        status: AccountStatus.active,
        mustChangePassword: true,
        passwordHash: passwordHash,
        createdAt: now,
        updatedAt: now,
        createdById: createdById,
      ),
    );

    await _auditLog.insertEvent(
      eventTypeKey: 'account_created',
      actorAccountId: createdById,
      targetAccountId: internalId,
    );

    return internalId;
  }

  static String _generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}'
        '-${hex.substring(12, 16)}-${hex.substring(16, 20)}'
        '-${hex.substring(20)}';
  }
}
