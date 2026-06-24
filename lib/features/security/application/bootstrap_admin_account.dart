import '../../../core/time/clock.dart';
import '../domain/entities/account.dart';
import '../domain/entities/account_role.dart';
import '../domain/entities/account_status.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/security_audit_repository.dart';

/// Not a valid PHC string — [PasswordHasher.verify] always returns false for
/// it. Used as the admin's initial password hash so login is impossible until
/// [SetInitialAdminPassword] (or recovery) installs a real hash.
const String kSentinelPasswordHash = r'$sentinel$v=0$not-a-real-hash$';

/// Ensures the system administrator account exists in the database.
///
/// Idempotent: if an account with [internalId] == 'admin' already exists the
/// use case returns immediately without touching the database again. It is safe
/// to call on every application startup.
///
/// On first run it inserts the account with [_kSentinelHash] as the password
/// and [mustChangePassword] == true, forcing the initial-setup screen before
/// the administrator can use the system. It also records an 'admin_bootstrapped'
/// audit event so the first-run moment is traceable.
class BootstrapAdminAccount {
  const BootstrapAdminAccount({
    required this._accounts,
    required this._auditLog,
    required this._clock,
  });

  final AccountRepository _accounts;
  final SecurityAuditRepository _auditLog;
  final Clock _clock;

  Future<void> call() async {
    final existing = await _accounts.findById('admin');
    if (existing != null) return;

    final now = _clock.nowUtc();
    await _accounts.insertAccount(
      Account(
        internalId: 'admin',
        username: 'marjiy@admin',
        displayName: 'مدير النظام',
        role: AccountRole.admin,
        status: AccountStatus.active,
        mustChangePassword: true,
        passwordHash: kSentinelPasswordHash,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _auditLog.insertEvent(
      eventTypeKey: 'admin_bootstrapped',
      actorAccountId: 'admin',
    );
  }
}
