// lib/features/security/application/step_up_required_exception.dart

/// Thrown when a sensitive administrator operation is attempted without a valid
/// step-up authentication approval.
///
/// Unlike [UnauthorizedException] (wrong role / no session), this exception
/// signals that the caller IS an admin but has not re-verified their password
/// via [VerifyAdminStepUp] within the current step-up window.
class StepUpRequiredException implements Exception {
  const StepUpRequiredException();

  @override
  String toString() => 'StepUpRequiredException';
}
