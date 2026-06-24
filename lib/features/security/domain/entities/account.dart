import 'package:equatable/equatable.dart';

import 'account_role.dart';
import 'account_status.dart';

/// A user account in the MARJIY system.
///
/// [internalId] is immutable after creation: 'admin' for the administrator,
/// a stable UUID for each operator. [username] must be unique across all
/// accounts. [passwordHash] is an Argon2id PHC-format string — never a
/// plaintext password. [mustChangePassword] forces a password-change screen on
/// first login for accounts created with a temporary password.
class Account extends Equatable {
  const Account({
    required this.internalId,
    required this.username,
    required this.displayName,
    required this.role,
    required this.status,
    required this.mustChangePassword,
    required this.passwordHash,
    required this.createdAt,
    required this.updatedAt,
    this.createdById,
  });

  final String internalId;
  final String username;
  final String displayName;
  final AccountRole role;
  final AccountStatus status;
  final bool mustChangePassword;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdById;

  Account copyWith({
    String? username,
    String? displayName,
    AccountStatus? status,
    bool? mustChangePassword,
    String? passwordHash,
    DateTime? updatedAt,
  }) => Account(
    internalId: internalId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    role: role,
    status: status ?? this.status,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    passwordHash: passwordHash ?? this.passwordHash,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdById: createdById,
  );

  @override
  List<Object?> get props => [
    internalId,
    username,
    displayName,
    role,
    status,
    mustChangePassword,
    passwordHash,
    createdAt,
    updatedAt,
    createdById,
  ];
}
