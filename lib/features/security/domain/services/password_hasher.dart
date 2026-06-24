/// Persistence-agnostic contract for password hashing and verification.
///
/// Implementations must use a memory-hard algorithm (Argon2id) and store
/// parameters alongside the hash so that future parameter upgrades are
/// possible without invalidating existing hashes. Passwords are never
/// stored in plaintext or in a reversible form.
abstract class PasswordHasher {
  /// Hashes [password] and returns a self-describing PHC-format string that
  /// includes the algorithm, parameters, salt, and hash — never the password.
  Future<String> hash(String password);

  /// Returns true if [password] matches [storedHash]; false otherwise.
  ///
  /// [storedHash] must be a value previously returned by [hash]. An
  /// unrecognised or malformed [storedHash] silently returns false so that
  /// sentinel hashes and format errors cannot be distinguished from wrong
  /// passwords (no oracle for attackers).
  Future<bool> verify(String password, String storedHash);
}
