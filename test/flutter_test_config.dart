import 'dart:async';

import 'package:drift/drift.dart';

// Runs before every test in the test/ directory.
// Suppresses the "multiple AppDatabase instances" warning that Drift emits
// when integration tests open more than one in-memory database concurrently.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
