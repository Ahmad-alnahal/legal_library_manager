sealed class RecoveryEvent {
  const RecoveryEvent();
}

final class RecoverySubmitted extends RecoveryEvent {
  const RecoverySubmitted(this.recoveryKey);
  final String recoveryKey;
}

final class RecoveryErrorDismissed extends RecoveryEvent {
  const RecoveryErrorDismissed();
}
