import 'package:flutter/material.dart';

import 'app/marjiy_bootstrap.dart';
import 'core/di/injection.dart';
import 'features/security/presentation/pages/auth_gate_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  runApp(const MarjiyBootstrap(readyHome: AuthGatePage()));
}
