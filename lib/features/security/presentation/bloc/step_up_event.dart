// lib/features/security/presentation/bloc/step_up_event.dart

import 'package:equatable/equatable.dart';

sealed class StepUpEvent extends Equatable {
  const StepUpEvent();
  @override
  List<Object?> get props => [];
}

/// The administrator has entered a password and submitted the step-up dialog.
final class StepUpPasswordSubmitted extends StepUpEvent {
  const StepUpPasswordSubmitted(this.password);
  final String password;
  @override
  List<Object?> get props => [password];
}

/// The user dismissed the error state without retrying.
final class StepUpErrorDismissed extends StepUpEvent {
  const StepUpErrorDismissed();
}
