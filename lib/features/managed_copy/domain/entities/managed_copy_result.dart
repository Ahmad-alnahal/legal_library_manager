// lib/features/managed_copy/domain/entities/managed_copy_result.dart

import 'managed_copy_error.dart';

/// Sealed result hierarchy for a managed-copy operation.
sealed class ManagedCopyResult {
  const ManagedCopyResult();
}

/// The copy completed, verified, and persisted successfully.
final class ManagedCopySuccess extends ManagedCopyResult {
  const ManagedCopySuccess({
    required this.documentFileId,
    required this.documentCode,
    required this.managedPath,
    required this.sha256Hash,
  });

  final int documentFileId;
  final String documentCode;
  final String managedPath;
  final String sha256Hash;
}

/// A pre-flight safety check blocked the operation; no copy was attempted and
/// no bytes were written.
final class ManagedCopyBlocked extends ManagedCopyResult {
  const ManagedCopyBlocked({required this.error, required this.safeMessage});

  final ManagedCopyError error;
  final String safeMessage;
}

/// A copy-stage failure occurred; no successful DB state was written.
final class ManagedCopyFailed extends ManagedCopyResult {
  const ManagedCopyFailed({required this.error, required this.safeMessage});

  final ManagedCopyError error;
  final String safeMessage;
}

/// The copy file was finalized and verified but subsequent DB persistence
/// failed. The verified managed file exists at [verifiedPath] and must be
/// reconciled (handled in M11). No successful workflow state exists.
final class ManagedCopyRecoveryRequired extends ManagedCopyResult {
  const ManagedCopyRecoveryRequired({
    required this.verifiedPath,
    required this.safeMessage,
  });

  final String verifiedPath;
  final String safeMessage;
}
