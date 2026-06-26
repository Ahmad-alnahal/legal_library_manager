// lib/features/word_conversion/domain/services/microsoft_word_probe.dart

/// Outcome of a single Microsoft Word probe attempt.
sealed class MicrosoftWordProbeResult {
  const MicrosoftWordProbeResult();
}

/// A usable local Microsoft Word automation host was located.
final class MicrosoftWordFound extends MicrosoftWordProbeResult {
  const MicrosoftWordFound({required this.executablePath, this.version});

  /// Absolute path or executable name for the local automation host.
  final String executablePath;

  /// Parsed Word version string, or null when version detection was
  /// unsuccessful.
  final String? version;
}

/// Microsoft Word could not be found or automated on this machine.
final class MicrosoftWordNotFound extends MicrosoftWordProbeResult {
  const MicrosoftWordNotFound();
}

/// Injectable boundary for detecting local Microsoft Word availability.
///
/// Implementations live in the data layer and may use `dart:io` and process
/// invocation APIs. Domain and application layers depend only on this
/// interface; they never import `dart:io` or invoke processes directly.
///
/// Contract: [probe] must never throw. All OS-level errors must be absorbed
/// and mapped to [MicrosoftWordNotFound] by the implementing class.
abstract class MicrosoftWordProbe {
  /// Probes the local system for a licensed Microsoft Word installation that
  /// can be automated locally.
  Future<MicrosoftWordProbeResult> probe();
}
