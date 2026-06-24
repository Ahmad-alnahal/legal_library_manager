/// Lifecycle status of an account.
///
/// [active]: the account may log in normally.
/// [suspended]: the account is blocked from logging in; the administrator may
///   reactivate it. Triggered by exceeding the failed-login limit.
/// [disabled]: the account is permanently deactivated; only the administrator
///   can re-enable it through an explicit administrative action.
enum AccountStatus { active, suspended, disabled }
