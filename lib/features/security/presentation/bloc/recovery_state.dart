sealed class RecoveryState {
  const RecoveryState();
}

final class RecoveryInitial extends RecoveryState {
  const RecoveryInitial();
}

final class RecoveryInProgress extends RecoveryState {
  const RecoveryInProgress();
}

/// Recovery succeeded. [newRecoveryKey] is the rotated key for one-time
/// display — the caller must show it before navigating away.
final class RecoverySuccess extends RecoveryState {
  const RecoverySuccess(this.newRecoveryKey);
  final String newRecoveryKey;
}

final class RecoveryError extends RecoveryState {
  const RecoveryError(this.messageKey, {this.remainingSeconds});
  final String messageKey;

  /// Non-null when [messageKey] == 'throttled'; the seconds remaining in the
  /// throttle window.
  final int? remainingSeconds;
}
