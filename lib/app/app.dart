import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/presentation/pages/app_shell_page.dart';
import '../l10n/app_localizations.dart';

/// Root application widget for MARJIY.
///
/// Arabic-first and RTL by default: the single supported locale is `ar`, which
/// drives Material's text direction to right-to-left for the whole app.
class MarjiyApp extends StatelessWidget {
  const MarjiyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppShellPage(),
    );
  }
}
