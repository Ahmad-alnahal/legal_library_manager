import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/database/seeding/reference_seeder.dart';
import 'core/database/seeding/settings_seeder.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();

  // Seed finalized reference data and default settings before the UI is shown,
  // so the import workflow and reference lookups are usable immediately. Both
  // seeders are idempotent and transactional.
  final AppDatabase database = getIt<AppDatabase>();
  await ReferenceSeeder(database).seedAll();
  await SettingsSeeder(database).seedDefaults();

  runApp(const MarjiyApp());
}
