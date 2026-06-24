import 'dart:math';
import 'dart:typed_data';

import '../../../../core/time/clock.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';
import '../domain/services/password_hasher.dart';

/// Minimum password length enforced by this use case.
const int kMinPasswordLength = 8;

/// Thrown when the provided password does not meet the minimum requirements.
final class WeakPasswordException implements Exception {
  const WeakPasswordException(this.message);
  final String message;
  @override
  String toString() => 'WeakPasswordException: $message';
}

/// Sets the administrator password on first launch, stores the Argon2id hash
/// of a generated recovery key, and returns the raw key for one-time display.
///
/// This use case is idempotent if called with a valid password: subsequent
/// calls simply overwrite the existing hash and generate a new recovery key.
/// The raw key is returned to the caller for display only and is never
/// persisted.
///
/// **Recovery key format:** 128 bits (16 bytes) encoded as four groups of
/// four uppercase hex pairs separated by dashes, e.g.:
/// `A3F7-92BC-1D4E-8F60-7A2B-C9D1-E5F3-0842`
class SetInitialAdminPassword {
  const SetInitialAdminPassword({
    required this._accounts,
    required this._hasher,
    required this._auditLog,
    required this._clock,
  });

  final AccountRepository _accounts;
  final PasswordHasher _hasher;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;

  /// Sets the admin password and returns the new recovery key for display.
  ///
  /// Throws [WeakPasswordException] if [newPassword] is shorter than
  /// [kMinPasswordLength] characters.
  Future<String> call(String newPassword) async {
    if (newPassword.length < kMinPasswordLength) {
      throw const WeakPasswordException(
        'Password must be at least 8 characters.',
      );
    }

    final admin = await _accounts.findById('admin');
    if (admin == null) {
      throw StateError(
        'Admin account not found — run BootstrapAdminAccount first.',
      );
    }

    final passwordHash = await _hasher.hash(newPassword);
    await _accounts.updateAccount(
      admin.copyWith(
        passwordHash: passwordHash,
        mustChangePassword: false,
        updatedAt: _clock.nowUtc(),
      ),
    );

    final rawKey = _generateRecoveryKey();
    final keyHash = await _hasher.hash(rawKey);
    await _accounts.upsertRecoveryCredentials(
      'admin',
      keyHash,
      _clock.nowUtc(),
    );

    await _auditLog.insertEvent(
      eventTypeKey: 'password_changed',
      actorAccountId: 'admin',
    );

    return rawKey;
  }

  String _generateRecoveryKey() => generateRecoveryKey();
}

/// Generates a 128-bit random key as uppercase hex with dashes.
///
/// Format: `XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX` where each group is 8
/// uppercase hex digits (4 bytes). Total length: 35 characters.
String generateRecoveryKey() {
  final rng = Random.secure();
  final bytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  return [
    hex.substring(0, 8),
    hex.substring(8, 16),
    hex.substring(16, 24),
    hex.substring(24, 32),
  ].join('-');
}
