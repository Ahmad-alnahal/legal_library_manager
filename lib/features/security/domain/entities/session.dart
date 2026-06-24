import 'package:equatable/equatable.dart';

import 'account_role.dart';

/// An active in-memory user session.
///
/// Sessions are never persisted — they are created on successful login and
/// destroyed on logout, close, crash, or restart. Admin sessions also expire
/// after 30 minutes of inactivity (managed by [SessionManager]).
///
/// [isRestrictedToPasswordChange] is true when the account had
/// [Account.mustChangePassword] set at login time; the shell routes such
/// sessions to the password-change screen before normal access is granted.
class Session extends Equatable {
  const Session({
    required this.accountId,
    required this.username,
    required this.role,
    required this.startedAt,
    this.isRestrictedToPasswordChange = false,
  });

  final String accountId;
  final String username;
  final AccountRole role;
  final DateTime startedAt;
  final bool isRestrictedToPasswordChange;

  Session copyWith({bool? isRestrictedToPasswordChange}) => Session(
        accountId: accountId,
        username: username,
        role: role,
        startedAt: startedAt,
        isRestrictedToPasswordChange:
            isRestrictedToPasswordChange ?? this.isRestrictedToPasswordChange,
      );

  @override
  List<Object?> get props => [
        accountId,
        username,
        role,
        startedAt,
        isRestrictedToPasswordChange,
      ];
}
