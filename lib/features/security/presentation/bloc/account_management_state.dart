import 'package:equatable/equatable.dart';

import '../../domain/entities/account.dart';

sealed class AccountManagementState extends Equatable {
  const AccountManagementState();
}

final class AccountManagementInitial extends AccountManagementState {
  const AccountManagementInitial();
  @override
  List<Object?> get props => [];
}

final class AccountManagementLoading extends AccountManagementState {
  const AccountManagementLoading();
  @override
  List<Object?> get props => [];
}

final class AccountManagementLoaded extends AccountManagementState {
  const AccountManagementLoaded({required this.operators, this.admin});
  final List<Account> operators;
  final Account? admin;
  @override
  List<Object?> get props => [operators, admin];
}

final class AccountManagementOperating extends AccountManagementState {
  const AccountManagementOperating({required this.operators, this.admin});
  final List<Account> operators;
  final Account? admin;
  @override
  List<Object?> get props => [operators, admin];
}

final class AccountManagementError extends AccountManagementState {
  const AccountManagementError({
    required this.messageKey,
    required this.operators,
    this.admin,
  });
  final String messageKey;
  final List<Account> operators;
  final Account? admin;
  @override
  List<Object?> get props => [messageKey, operators, admin];
}
