// lib/features/managed_copy/domain/services/local_file_availability_checker.dart

/// Checks whether a file is fully present on local disk, as opposed to a
/// cloud-sync placeholder (e.g. OneDrive Files On-Demand "online-only" file)
/// that would trigger a network download if read or copied.
///
/// Implementations live in the data layer and may use FFI/Win32 APIs. Domain
/// and application layers depend only on this abstraction.
abstract class LocalFileAvailabilityChecker {
  /// Returns true when [absolutePath] can be read without triggering a
  /// network fetch. Returns true (assume available) whenever the check
  /// itself cannot be completed — a failed probe must never block a
  /// genuinely local file; the actual read/copy attempt remains the
  /// authoritative safety net for real I/O failures.
  bool isLocallyAvailable(String absolutePath);
}
