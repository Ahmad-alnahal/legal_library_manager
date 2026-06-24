import 'package:equatable/equatable.dart';

sealed class PasswordChangeEvent extends Equatable {
  const PasswordChangeEvent();
}

final class PasswordChangeSubmitted extends PasswordChangeEvent {
  const PasswordChangeSubmitted({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;
  @override
  List<Object?> get props => [currentPassword, newPassword, confirmPassword];
}

final class PasswordChangeErrorDismissed extends PasswordChangeEvent {
  const PasswordChangeErrorDismissed();
  @override
  List<Object?> get props => [];
}
