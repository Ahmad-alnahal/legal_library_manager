import 'package:equatable/equatable.dart';

/// The current failed-login tracking state for one account.
///
/// [consecutiveFailures] counts uninterrupted failures since the last
/// successful login or reset. [unlockNotBefore] is the UTC time before which
/// login attempts must be rejected (null when no delay is active).
/// [lastFailedAt] is used to detect clock rollback: if the system clock is
/// behind this value on a new attempt, the delay is extended. The recovery
/// fields track offline recovery-key attempts separately from login failures.
class FailedLoginState extends Equatable {
  const FailedLoginState({
    required this.consecutiveFailures,
    this.unlockNotBefore,
    this.lastFailedAt,
    this.lastSucceededAt,
    this.recoveryAttemptCount = 0,
    this.recoveryWindowStart,
  });

  final int consecutiveFailures;
  final DateTime? unlockNotBefore;
  final DateTime? lastFailedAt;
  final DateTime? lastSucceededAt;
  final int recoveryAttemptCount;
  final DateTime? recoveryWindowStart;

  FailedLoginState copyWith({
    int? consecutiveFailures,
    DateTime? unlockNotBefore,
    bool clearUnlockNotBefore = false,
    DateTime? lastFailedAt,
    DateTime? lastSucceededAt,
    int? recoveryAttemptCount,
    DateTime? recoveryWindowStart,
    bool clearRecoveryWindow = false,
  }) => FailedLoginState(
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    unlockNotBefore: clearUnlockNotBefore
        ? null
        : (unlockNotBefore ?? this.unlockNotBefore),
    lastFailedAt: lastFailedAt ?? this.lastFailedAt,
    lastSucceededAt: lastSucceededAt ?? this.lastSucceededAt,
    recoveryAttemptCount: recoveryAttemptCount ?? this.recoveryAttemptCount,
    recoveryWindowStart: clearRecoveryWindow
        ? null
        : (recoveryWindowStart ?? this.recoveryWindowStart),
  );

  @override
  List<Object?> get props => [
    consecutiveFailures,
    unlockNotBefore,
    lastFailedAt,
    lastSucceededAt,
    recoveryAttemptCount,
    recoveryWindowStart,
  ];
}
