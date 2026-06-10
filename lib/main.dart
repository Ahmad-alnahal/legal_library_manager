import 'package:flutter/material.dart';

import 'app/marjiy_bootstrap.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  runApp(const MarjiyBootstrap());
}
