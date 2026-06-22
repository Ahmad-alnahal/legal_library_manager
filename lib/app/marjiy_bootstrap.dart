import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/database/seeding/reference_seeder.dart';
import '../core/database/seeding/settings_seeder.dart';
import '../core/di/injection.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_spacing.dart';
import '../core/widgets/app_panel.dart';
import '../features/managed_copy/application/initialize_copy_roots.dart';
import '../features/managed_copy/application/inspect_startup_recovery.dart';
import '../features/shell/presentation/pages/app_shell_page.dart';
import '../l10n/app_localizations.dart';
import 'app.dart';

typedef StartupInitializer = Future<void> Function();
typedef StartupErrorReporter = void Function(Object error, StackTrace stack);

/// Opens and prepares the production database before the operational shell is
/// shown. Both seeders are transactional and idempotent.
Future<void> initializeApplication() async {
  final AppDatabase database = getIt<AppDatabase>();
  await ReferenceSeeder(database).seedAll();
  await SettingsSeeder(database).seedDefaults();
  // M8.4: configure default copy roots under <Documents>\MARJIY. Never
  // throws; failures surface as a requires-attention state in Settings and
  // keep managed-copy actions blocked without blocking the rest of the app.
  await getIt<InitializeCopyRoots>()();
  // M11.2: record a safe status for interrupted app-owned managed-copy
  // artifacts. This never repairs or deletes files.
  await getIt<InspectStartupRecovery>()();
}

void _reportStartupError(Object error, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'MARJIY startup',
      context: ErrorDescription('while preparing the local application data'),
    ),
  );
}

/// Owns application initialization and keeps startup failures visible and
/// recoverable. Failure details are never rendered in the UI.
class MarjiyBootstrap extends StatefulWidget {
  const MarjiyBootstrap({
    super.key,
    this.initializer = initializeApplication,
    this.errorReporter = _reportStartupError,
    this.readyHome = const AppShellPage(),
  });

  final StartupInitializer initializer;
  final StartupErrorReporter errorReporter;
  final Widget readyHome;

  @override
  State<MarjiyBootstrap> createState() => _MarjiyBootstrapState();
}

class _MarjiyBootstrapState extends State<MarjiyBootstrap> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    try {
      await widget.initializer();
    } catch (error, stack) {
      widget.errorReporter(error, stack);
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _initialization = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MarjiyApp(
      home: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupLoadingView();
          }
          if (snapshot.hasError) {
            return _StartupFailureView(onRetry: _retry);
          }
          return widget.readyHome;
        },
      ),
    );
  }
}

class _StartupLoadingView extends StatelessWidget {
  const _StartupLoadingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Semantics(
          label: l10n.startupLoading,
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App logo mark — matches the shell header brand block.
              Image.asset('assets/images/logo_mark.png', width: 64, height: 64),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.appTitle, style: text.titleLarge),
              const SizedBox(height: AppSpacing.xxl),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.startupLoading),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupFailureView extends StatelessWidget {
  const _StartupFailureView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: AppPanel(
                      borderColor: AppColors.borderStrong,
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFF7ED),
                                borderRadius: AppRadii.control,
                              ),
                              child: const Icon(
                                Icons.storage_outlined,
                                color: Color(0xFFB45309),
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              l10n.startupFailureTitle,
                              style: text.headlineSmall,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              l10n.startupFailureBody,
                              style: text.bodyLarge,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              l10n.startupSafetyNote,
                              style: text.bodyMedium?.copyWith(
                                color: AppColors.accentTeal,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: FilledButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(l10n.startupRetry),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
