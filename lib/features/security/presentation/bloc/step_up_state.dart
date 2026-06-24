// lib/features/security/presentation/bloc/step_up_state.dart

import 'package:equatable/equatable.dart';

sealed class StepUpState extends Equatable {
  const StepUpState();
  @override
  List<Object?> get props => [];
}

/// Initial idle state — no verification in progress.
final class StepUpInitial extends StepUpState {
  const StepUpInitial();
}

/// Password verification is in progress.
final class StepUpVerifying extends StepUpState {
  const StepUpVerifying();
}

/// Password verified — step-up approval has been granted.
final class StepUpSuccess extends StepUpState {
  const StepUpSuccess();
}

/// Verification failed.
///
/// [messageKey] values:
/// - `'wrongPassword'` — the password was incorrect.
/// - `'unexpected'`    — an unexpected error occurred.
final class StepUpError extends StepUpState {
  const StepUpError(this.messageKey);
  final String messageKey;
  @override
  List<Object?> get props => [messageKey];
}
