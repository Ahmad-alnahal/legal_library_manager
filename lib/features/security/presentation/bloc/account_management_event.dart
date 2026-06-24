import 'package:equatable/equatable.dart';

sealed class AccountManagementEvent extends Equatable {
  const AccountManagementEvent();
}

final class AccountManagementLoadRequested extends AccountManagementEvent {
  const AccountManagementLoadRequested();
  @override
  List<Object?> get props => [];
}

final class AccountManagementCreateOperator extends AccountManagementEvent {
  const AccountManagementCreateOperator({
    required this.username,
    required this.displayName,
    required this.temporaryPassword,
  });
  final String username;
  final String displayName;
  final String temporaryPassword;
  @override
  List<Object?> get props => [username, displayName, temporaryPassword];
}

final class AccountManagementSuspend extends AccountManagementEvent {
  const AccountManagementSuspend(this.operatorId);
  final String operatorId;
  @override
  List<Object?> get props => [operatorId];
}

final class AccountManagementReactivate extends AccountManagementEvent {
  const AccountManagementReactivate(this.operatorId);
  final String operatorId;
  @override
  List<Object?> get props => [operatorId];
}

final class AccountManagementIssueTempPassword extends AccountManagementEvent {
  const AccountManagementIssueTempPassword({
    required this.operatorId,
    required this.temporaryPassword,
  });
  final String operatorId;
  final String temporaryPassword;
  @override
  List<Object?> get props => [operatorId, temporaryPassword];
}

final class AccountManagementErrorDismissed extends AccountManagementEvent {
  const AccountManagementErrorDismissed();
  @override
  List<Object?> get props => [];
}
