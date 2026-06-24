/// The role of an account, determining which actions it may perform.
///
/// [admin] is the single administrator account (internal_id = 'admin').
/// [operator] covers all operator accounts created by the administrator.
enum AccountRole { admin, operator }
