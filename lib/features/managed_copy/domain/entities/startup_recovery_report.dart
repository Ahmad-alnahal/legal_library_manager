// lib/features/managed_copy/domain/entities/startup_recovery_report.dart

enum StartupRecoveryStatus { healthy, requiresAttention, inspectionFailed }

class StartupRecoveryReport {
  const StartupRecoveryReport({required this.status, this.artifactCount = 0});

  final StartupRecoveryStatus status;
  final int artifactCount;

  bool get requiresAttention =>
      status == StartupRecoveryStatus.requiresAttention ||
      status == StartupRecoveryStatus.inspectionFailed;

  static const healthy = StartupRecoveryReport(
    status: StartupRecoveryStatus.healthy,
  );
}
