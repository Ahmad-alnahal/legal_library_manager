import 'package:equatable/equatable.dart';

import '../../domain/entities/session.dart';

sealed class LoginState extends Equatable {
  const LoginState();
}

final class LoginInitial extends LoginState {
  const LoginInitial();
  @override
  List<Object?> get props => [];
}

final class LoginInProgress extends LoginState {
  const LoginInProgress();
  @override
  List<Object?> get props => [];
}

final class LoginSuccess extends LoginState {
  const LoginSuccess(this.session);
  final Session session;
  @override
  List<Object?> get props => [session];
}

final class LoginInvalidCredentials extends LoginState {
  const LoginInvalidCredentials();
  @override
  List<Object?> get props => [];
}

final class LoginAccountSuspended extends LoginState {
  const LoginAccountSuspended();
  @override
  List<Object?> get props => [];
}

final class LoginDelayed extends LoginState {
  const LoginDelayed(this.remainingSeconds);
  final int remainingSeconds;
  @override
  List<Object?> get props => [remainingSeconds];
}
