import 'package:equatable/equatable.dart';

sealed class InitialSetupEvent extends Equatable {
  const InitialSetupEvent();
}

final class SetupPasswordSubmitted extends InitialSetupEvent {
  const SetupPasswordSubmitted({
    required this.password,
    required this.confirmPassword,
  });
  final String password;
  final String confirmPassword;
  @override
  List<Object?> get props => [password, confirmPassword];
}

final class SetupKeyConfirmed extends InitialSetupEvent {
  const SetupKeyConfirmed();
  @override
  List<Object?> get props => [];
}
