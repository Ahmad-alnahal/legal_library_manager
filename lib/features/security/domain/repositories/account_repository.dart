import '../entities/account.dart';
import '../entities/failed_login_state.dart';

/// Persistence-agnostic contract for account and security-state operations.
///
/// All mutations are transactional in the implementation. No method exposes
/// password hashes in a way that allows them to be read in bulk — individual
/// lookups for authentication purposes return the full [Account] including
/// [Account.passwordHash] so that [PasswordHasher.verify] can be called.
/// Callers must never log or transmit the hash.
abstract class AccountRepository {
  /// Returns the account with [username], or null if not found.
  Future<Account?> findByUsername(String username);

  /// Returns the account with [internalId], or null if not found.
  Future<Account?> findById(String internalId);

  /// Inserts [account] as a new row. Throws if [account.internalId] or
  /// [account.username] already exists.
  Future<void> insertAccount(Account account);

  /// Updates all mutable fields of [account]. The [internalId] and [role] are
  /// never changed after creation.
  Future<void> updateAccount(Account account);

  /// Returns the current [FailedLoginState] for [accountId], or null if no
  /// state row exists yet (treat as zero failures, no active delay).
  Future<FailedLoginState?> getSecurityState(String accountId);

  /// Inserts or replaces the [FailedLoginState] for [accountId].
  Future<void> upsertSecurityState(String accountId, FailedLoginState state);

  /// Resets the security state for [accountId] to zero failures, no delay,
  /// and records [lastSucceededAt] as the current time.
  Future<void> resetSecurityState(String accountId, DateTime succeededAt);

  /// Inserts or replaces the recovery credential hash for [accountId].
  ///
  /// The raw recovery key is never passed here — only the Argon2id hash of the
  /// key. The caller is responsible for discarding the raw key immediately
  /// after returning it to the UI for one-time display.
  Future<void> upsertRecoveryCredentials(
    String accountId,
    String keyHash,
    DateTime createdAt,
  );

  /// Returns true if a recovery credential row exists for [accountId].
  Future<bool> hasRecoveryCredentials(String accountId);

  /// Returns the stored Argon2id hash of the recovery key for [accountId],
  /// or null if no recovery credential has been set up.
  Future<String?> getRecoveryKeyHash(String accountId);

  /// Returns all accounts with role [AccountRole.operator], ordered by
  /// creation date ascending. The admin account is never included.
  Future<List<Account>> listOperators();
}
