import 'package:equatable/equatable.dart';

sealed class InitialSetupState extends Equatable {
  const InitialSetupState();
}

final class SetupInitial extends InitialSetupState {
  const SetupInitial();
  @override
  List<Object?> get props => [];
}

final class SetupInProgress extends InitialSetupState {
  const SetupInProgress();
  @override
  List<Object?> get props => [];
}

/// Password was hashed and stored. The recovery key must now be shown to the
/// user and confirmed before the setup is considered complete.
final class SetupPasswordSet extends InitialSetupState {
  const SetupPasswordSet(this.recoveryKey);
  final String recoveryKey;
  @override
  List<Object?> get props => [recoveryKey];
}

final class SetupComplete extends InitialSetupState {
  const SetupComplete();
  @override
  List<Object?> get props => [];
}

final class SetupError extends InitialSetupState {
  const SetupError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
