import 'package:equatable/equatable.dart';

sealed class PasswordChangeState extends Equatable {
  const PasswordChangeState();
}

final class PasswordChangeInitial extends PasswordChangeState {
  const PasswordChangeInitial();
  @override
  List<Object?> get props => [];
}

final class PasswordChangeInProgress extends PasswordChangeState {
  const PasswordChangeInProgress();
  @override
  List<Object?> get props => [];
}

final class PasswordChangeSuccess extends PasswordChangeState {
  const PasswordChangeSuccess();
  @override
  List<Object?> get props => [];
}

final class PasswordChangeError extends PasswordChangeState {
  const PasswordChangeError(this.messageKey);
  final String messageKey;
  @override
  List<Object?> get props => [messageKey];
}
