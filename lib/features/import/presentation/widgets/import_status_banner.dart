// lib/features/import/presentation/widgets/import_status_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../shell/domain/entities/app_section.dart';
import '../../../shell/presentation/bloc/navigation_bloc.dart';
import '../../application/import_job_snapshot.dart';
import '../../application/import_progress.dart';
import '../bloc/import_status_bloc.dart';

/// App-wide import progress/result strip rendered at the bottom of the shell.
///
/// Creates its own [ImportStatusBloc] from GetIt. The [NavigationBloc] must
/// already be provided by an ancestor (the shell provides it).
///
/// [blocOverride] is accepted only in tests (annotated [@visibleForTesting])
/// to inject a pre-built bloc without touching the global GetIt registry.
class ImportStatusBanner extends StatelessWidget {
  const ImportStatusBanner({super.key}) : _blocOverride = null;

  @visibleForTesting
  const ImportStatusBanner.withBloc(ImportStatusBloc bloc, {super.key})
    : _blocOverride = bloc;

  final ImportStatusBloc? _blocOverride;

  @override
  Widget build(BuildContext context) {
    // In production the provider owns the bloc and closes it on dispose.
    // In tests (withBloc constructor) we use .value so the test controls the
    // lifecycle and BlocProvider.create's eager-close behavior cannot interfere.
    if (_blocOverride case final bloc?) {
      return BlocProvider<ImportStatusBloc>.value(
        value: bloc,
        child: const _ImportStatusBannerBody(),
      );
    }
    return BlocProvider<ImportStatusBloc>(
      create: (_) => getIt<ImportStatusBloc>(),
      child: const _ImportStatusBannerBody(),
    );
  }
}

class _ImportStatusBannerBody extends StatelessWidget {
  const _ImportStatusBannerBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ImportStatusBloc, ImportStatusState>(
      builder: (context, state) {
        if (!state.isVisible) return const SizedBox.shrink();
        return _BannerContent(state: state);
      },
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({required this.state});

  final ImportStatusState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snap = state.snapshot;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isActive = snap.isActive;

    final Color bgColor = isActive
        ? colors.primaryContainer
        : snap.status == ImportJobStatus.completed
        ? colors.secondaryContainer
        : colors.errorContainer;

    final Color fgColor = isActive
        ? colors.onPrimaryContainer
        : snap.status == ImportJobStatus.completed
        ? colors.onSecondaryContainer
        : colors.onErrorContainer;

    final String statusLabel = switch (snap.status) {
      ImportJobStatus.running => l10n.importBannerRunning,
      ImportJobStatus.cancelling => l10n.importBannerCancelling,
      ImportJobStatus.completed => l10n.importBannerCompleted,
      ImportJobStatus.cancelled => l10n.importBannerCancelled,
      ImportJobStatus.failed => l10n.importBannerFailed,
      ImportJobStatus.idle => '',
    };

    return Material(
      elevation: 4,
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isActive)
              _ProgressRow(snap: snap, fgColor: fgColor, l10n: l10n),
            Row(
              children: [
                Expanded(
                  child: Text(
                    statusLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: fgColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.read<NavigationBloc>().add(
                    NavigationSectionSelected(AppSection.import),
                  ),
                  child: Text(l10n.importBannerGoToImport),
                ),
                if (isActive)
                  TextButton(
                    onPressed: () => context.read<ImportStatusBloc>().add(
                      const ImportStatusCancelRequested(),
                    ),
                    child: Text(l10n.importBannerCancel),
                  ),
                if (snap.isTerminal)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.importBannerDismiss,
                    onPressed: () => context.read<ImportStatusBloc>().add(
                      const ImportStatusDismissRequested(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.snap,
    required this.fgColor,
    required this.l10n,
  });

  final ImportJobSnapshot snap;
  final Color fgColor;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ImportProgress? progress = snap.progress;
    final bool hasTotal = progress != null && progress.discovered > 0;
    final double? fraction = hasTotal ? progress.fraction : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: fraction),
        if (hasTotal)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.importBannerProgress(
                progress.processed,
                progress.discovered,
              ),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: fgColor),
              textAlign: TextAlign.end,
            ),
          ),
      ],
    );
  }
}
