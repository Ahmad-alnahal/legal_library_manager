import 'package:equatable/equatable.dart';

sealed class LoginEvent extends Equatable {
  const LoginEvent();
}

final class LoginSubmitted extends LoginEvent {
  const LoginSubmitted({required this.username, required this.password});
  final String username;
  final String password;
  @override
  List<Object?> get props => [username, password];
}

final class LoginErrorDismissed extends LoginEvent {
  const LoginErrorDismissed();
  @override
  List<Object?> get props => [];
}
