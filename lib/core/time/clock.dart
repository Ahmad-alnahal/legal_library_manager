// lib/core/time/clock.dart

/// Injectable source of the current time and year.
///
/// Domain/application code depends on this abstraction instead of calling
/// [DateTime.now] directly, so tests can supply a deterministic clock and all
/// persisted timestamps are UTC.
abstract class Clock {
  const Clock();

  /// The current instant in UTC.
  DateTime nowUtc();

  /// The current (UTC) calendar year — used by year-range validation.
  int get currentYear => nowUtc().year;
}

/// Production clock backed by the system wall clock, normalized to UTC.
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}
