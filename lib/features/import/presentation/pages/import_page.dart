// lib/features/import/presentation/pages/import_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/safety_banner.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/folder_picker.dart';
import '../../application/import_file_report.dart';
import '../../application/import_progress.dart';
import '../../application/import_run_report.dart';
import '../../domain/entities/folder_validation.dart';
import '../../domain/entities/import_error.dart';
import '../bloc/import_bloc.dart';
import '../bloc/import_history_bloc.dart';
import '../widgets/import_history_section.dart';

/// Import screen: provides [ImportBloc] and [ImportHistoryBloc], then
/// renders the workflow in [ImportView].
class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ImportBloc>(create: (_) => getIt<ImportBloc>()),
        BlocProvider<ImportHistoryBloc>(
          create: (_) => getIt<ImportHistoryBloc>(),
        ),
      ],
      child: ImportView(picker: getIt<FolderPicker>()),
    );
  }
}

/// The functional Arabic RTL import workflow. Assumes an [ImportBloc] is
/// provided above it; takes a [FolderPicker] so tests can inject a fake.
class ImportView extends StatelessWidget {
  const ImportView({super.key, required this.picker});

  final FolderPicker picker;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return BlocBuilder<ImportBloc, ImportState>(
      builder: (context, state) {
        return ScreenContainer(
          children: [
            PageHeader(title: l10n.importTitle, subtitle: l10n.importSubtitle),
            const SizedBox(height: AppSpacing.lg),
            SafetyBanner(
              title: l10n.sourceSafetyBannerTitle,
              message: l10n.sourceSafetyBannerBody,
            ),
            const SizedBox(height: AppSpacing.md),
            _ScanOnlyNote(text: l10n.importScanOnlyNote),
            const SizedBox(height: AppSpacing.lg),
            _SourcePanel(state: state, picker: picker),
            if (state.isActive) ...[
              const SizedBox(height: AppSpacing.lg),
              _ProgressPanel(state: state),
            ],
            if (state.status == ImportStatus.failed) ...[
              const SizedBox(height: AppSpacing.lg),
              _FailureSection(report: state.report),
            ] else if (state.isTerminal && state.report != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _ResultsSection(report: state.report!, status: state.status),
            ] else if (state.status == ImportStatus.idle) ...[
              const SizedBox(height: AppSpacing.lg),
              EmptyState(
                icon: Icons.folder_off_outlined,
                title: l10n.importEmptyTitle,
                message: l10n.importEmptyBody,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ImportHistorySection(
              isImportActive: state.isActive,
              onReuseFolder: (folder) =>
                  context.read<ImportBloc>().add(ImportFolderSelected(folder)),
            ),
          ],
        );
      },
    );
  }
}

class _ScanOnlyNote extends StatelessWidget {
  const _ScanOnlyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.tag_outlined,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({required this.state, required this.picker});

  final ImportState state;
  final FolderPicker picker;

  Future<void> _pick(BuildContext context) async {
    // Capture the BLoC before the await so we never touch a possibly-unmounted
    // context afterwards.
    final ImportBloc bloc = context.read<ImportBloc>();
    String? path;
    try {
      path = await picker.pickDirectory();
    } catch (_) {
      // A native picker failure must never crash the UI; treat as no selection.
      return;
    }
    // Cancellation (null/empty) selects nothing — and selection alone never
    // starts scanning. Guard against a BLoC closed while the dialog was open.
    if (path == null || path.trim().isEmpty || bloc.isClosed) return;
    bloc.add(ImportFolderSelected(path));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool enabled = !state.isActive;
    final String? folder = state.selectedFolder;

    return SectionPanel(
      title: l10n.importSourceFolderTitle,
      icon: Icons.folder_open_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final Widget field = _FolderField(
                path: folder,
                emptyLabel: l10n.importFolderFieldEmpty,
              );
              final Widget pick = AppSecondaryButton(
                label: l10n.importPickFolderButton,
                icon: Icons.drive_folder_upload_outlined,
                onPressed: enabled ? () => _pick(context) : null,
              );
              // Stack vertically when too narrow for a side-by-side row, so the
              // layout never overflows horizontally.
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field,
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: pick,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: AppSpacing.md),
                  pick,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _RecursiveToggle(value: state.recursive, enabled: enabled),
          const SizedBox(height: AppSpacing.lg),
          if (!state.isActive)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppPrimaryButton(
                label: l10n.importStartButton,
                icon: Icons.play_arrow_outlined,
                onPressed: state.canStart
                    ? () => context.read<ImportBloc>().add(
                        const ImportStartRequested(),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _FolderField extends StatelessWidget {
  const _FolderField({required this.path, required this.emptyLabel});

  final String? path;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final bool hasPath = path != null && path!.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: hasPath
          ? _PathText(path: path!)
          : Text(
              emptyLabel,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textDisabled),
            ),
    );
  }
}

/// Renders a filesystem path left-to-right (so it stays readable) inside the
/// RTL interface, truncating with an ellipsis rather than overflowing.
class _PathText extends StatelessWidget {
  const _PathText({required this.path, this.style});

  final String path;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style ?? Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _RecursiveToggle extends StatelessWidget {
  const _RecursiveToggle({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: enabled
          ? () => context.read<ImportBloc>().add(ImportRecursiveToggled(!value))
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: enabled
                  ? (v) => context.read<ImportBloc>().add(
                      ImportRecursiveToggled(v ?? false),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(child: Text(l10n.importRecursiveLabel)),
          ],
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.state});

  final ImportState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ImportProgress? progress = state.progress;
    final TextTheme text = Theme.of(context).textTheme;
    final String phaseLabel = state.status == ImportStatus.cancelling
        ? l10n.importPhaseCancelling
        : _phaseLabel(l10n, progress?.phase);

    return SectionPanel(
      title: l10n.importProgressTitle,
      icon: Icons.sync_outlined,
      trailing: AppSecondaryButton(
        label: l10n.importCancelButton,
        icon: Icons.stop_circle_outlined,
        onPressed: state.status == ImportStatus.cancelling
            ? null
            : () =>
                  context.read<ImportBloc>().add(const ImportCancelRequested()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(phaseLabel, style: text.titleSmall),
          if (progress?.currentFileName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text(
                  '${l10n.importCurrentFileLabel}: ',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Expanded(
                  child: _PathText(
                    path: progress!.currentFileName!,
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: (progress?.discovered ?? 0) > 0 ? progress!.fraction : null,
            minHeight: 8,
            backgroundColor: AppColors.surfaceMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.importProgressCount(
              progress?.processed ?? 0,
              progress?.discovered ?? 0,
            ),
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ResultsSection extends StatelessWidget {
  const _ResultsSection({required this.report, required this.status});

  final ImportRunReport report;
  final ImportStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TerminalBanner(status: status),
        const SizedBox(height: AppSpacing.md),
        _SummaryPanel(report: report),
        const SizedBox(height: AppSpacing.md),
        _FileResultsPanel(report: report),
        const SizedBox(height: AppSpacing.lg),
        _TerminalActions(report: report),
      ],
    );
  }
}

/// The per-file results list. Uses a lazily-built [ListView.separated] inside a
/// stable, responsive, bounded height so that even very large reports only
/// build the handful of rows currently visible (the rest are realized on
/// demand) and the list scrolls internally without breaking the page's own
/// scroll. Paths inside each row stay LTR-readable via [_PathText].
class _FileResultsPanel extends StatefulWidget {
  const _FileResultsPanel({required this.report});

  final ImportRunReport report;

  @override
  State<_FileResultsPanel> createState() => _FileResultsPanelState();
}

class _FileResultsPanelState extends State<_FileResultsPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<ImportFileReport> files = widget.report.files;
    return SectionPanel(
      title: l10n.importResultsTitle,
      icon: Icons.list_alt_outlined,
      child: files.isEmpty
          ? Text(
              l10n.importResultsEmpty,
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : SizedBox(
              // Scales with the window but stays within comfortable desktop
              // bounds, so it never grows unbounded inside the page scroll view.
              height: (MediaQuery.of(context).size.height * 0.5).clamp(
                200.0,
                560.0,
              ),
              child: Scrollbar(
                controller: _scrollController,
                child: ListView.separated(
                  controller: _scrollController,
                  primary: false,
                  itemCount: files.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) => _FileRow(file: files[index]),
                ),
              ),
            ),
    );
  }
}

class _TerminalBanner extends StatelessWidget {
  const _TerminalBanner({required this.status});

  final ImportStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (status) {
      ImportStatus.completed => SafetyBanner(
        title: l10n.importCompletedTitle,
        message: l10n.importScanOnlyNote,
        icon: Icons.check_circle_outline,
        tone: SafetyBannerTone.success,
      ),
      ImportStatus.cancelled => SafetyBanner(
        title: l10n.importCancelledTitle,
        message: l10n.importCancelledNote,
        icon: Icons.info_outline,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.report});

  final ImportRunReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppPanel(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          _SummaryStat(
            label: l10n.importSummaryNew,
            value: report.importedNewCount,
            status: AppStatusColors.success,
          ),
          _SummaryStat(
            label: l10n.importSummaryDuplicates,
            value: report.duplicateCount,
            status: AppStatusColors.duplicate,
          ),
          _SummaryStat(
            label: l10n.importSummaryAlreadyImported,
            value: report.alreadyImportedCount,
            status: AppStatusColors.neutral,
          ),
          if (report.pairedWordSourceCount > 0)
            _SummaryStat(
              label: l10n.importSummaryPairedWordSource,
              value: report.pairedWordSourceCount,
              status: AppStatusColors.neutral,
            ),
          _SummaryStat(
            label: l10n.importSummaryFailed,
            value: report.failedCount,
            status: AppStatusColors.danger,
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.status,
  });

  final String label;
  final int value;
  final StatusColor status;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: text.titleMedium?.copyWith(
              color: status.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final ImportFileReport file;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String? errorText = _errorText(l10n, file.error);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PathText(path: file.fileName, style: text.bodyMedium),
                const SizedBox(height: 2),
                _PathText(
                  path: file.path,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    errorText,
                    style: text.bodySmall?.copyWith(
                      color: AppStatusColors.danger.foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          StatusChip(
            label: _statusLabel(l10n, file.status),
            status: _statusColor(file.status),
          ),
        ],
      ),
    );
  }
}

class _TerminalActions extends StatelessWidget {
  const _TerminalActions({required this.report});

  final ImportRunReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        AppPrimaryButton(
          label: l10n.importResetButton,
          icon: Icons.refresh_outlined,
          onPressed: () =>
              context.read<ImportBloc>().add(const ImportResetRequested()),
        ),
        if (report.hasRetryableFailures)
          AppSecondaryButton(
            label: l10n.importRetryButton,
            icon: Icons.replay_outlined,
            onPressed: () =>
                context.read<ImportBloc>().add(const ImportRetryRequested()),
          ),
      ],
    );
  }
}

/// Failure terminal state. Always shows a clear failure banner — a
/// validation-specific protected-folder/readability message when the run failed
/// before a batch was created, or a generic coordinator-failure message
/// otherwise. When a failed report still carries partial per-file results, those
/// are shown safely below the banner (summary + virtualized list + actions).
class _FailureSection extends StatelessWidget {
  const _FailureSection({required this.report});

  final ImportRunReport? report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FolderValidationResult? validation = report?.validation;
    final String message = validation != null
        ? _validationMessage(l10n, validation.code)
        : l10n.importFailedGenericBody;
    final bool hasPartialResults = report != null && report!.files.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafetyBanner(
          title: l10n.importFailedTitle,
          message: message,
          icon: Icons.error_outline,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (hasPartialResults) ...[
          _SummaryPanel(report: report!),
          const SizedBox(height: AppSpacing.md),
          _FileResultsPanel(report: report!),
          const SizedBox(height: AppSpacing.lg),
          _TerminalActions(report: report!),
        ] else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppPrimaryButton(
              label: l10n.importResetButton,
              icon: Icons.refresh_outlined,
              onPressed: () =>
                  context.read<ImportBloc>().add(const ImportResetRequested()),
            ),
          ),
      ],
    );
  }
}

// --- label/color mapping helpers ---

String _phaseLabel(AppLocalizations l10n, ImportPhase? phase) {
  return switch (phase) {
    ImportPhase.validating => l10n.importPhaseValidating,
    ImportPhase.scanning => l10n.importPhaseScanning,
    ImportPhase.importing => l10n.importPhaseImporting,
    ImportPhase.finalizing => l10n.importPhaseFinalizing,
    null => l10n.importPhaseValidating,
  };
}

String _statusLabel(AppLocalizations l10n, ImportFileStatus status) {
  return switch (status) {
    ImportFileStatus.importedNew => l10n.importStatusImportedNew,
    ImportFileStatus.importedDuplicatePath =>
      l10n.importStatusImportedDuplicate,
    ImportFileStatus.alreadyImported => l10n.importStatusAlreadyImported,
    ImportFileStatus.unsupportedType => l10n.importStatusUnsupported,
    ImportFileStatus.unreadable => l10n.importStatusUnreadable,
    ImportFileStatus.hashFailed => l10n.importStatusHashFailed,
    ImportFileStatus.scanFailed => l10n.importStatusScanFailed,
    ImportFileStatus.persistenceFailed => l10n.importStatusPersistenceFailed,
    ImportFileStatus.corrupted => l10n.importStatusCorrupted,
    ImportFileStatus.pairedWordSource => l10n.importStatusPairedWordSource,
  };
}

StatusColor _statusColor(ImportFileStatus status) {
  return switch (status) {
    ImportFileStatus.importedNew => AppStatusColors.success,
    ImportFileStatus.importedDuplicatePath => AppStatusColors.duplicate,
    ImportFileStatus.alreadyImported => AppStatusColors.neutral,
    ImportFileStatus.unsupportedType => AppStatusColors.warning,
    ImportFileStatus.pairedWordSource => AppStatusColors.neutral,
    ImportFileStatus.unreadable ||
    ImportFileStatus.hashFailed ||
    ImportFileStatus.scanFailed ||
    ImportFileStatus.persistenceFailed ||
    ImportFileStatus.corrupted => AppStatusColors.danger,
  };
}

String? _errorText(AppLocalizations l10n, ImportError? error) {
  if (error == null) return null;
  return switch (error.code) {
    ImportErrorCode.unreadable => l10n.importStatusUnreadable,
    ImportErrorCode.hashFailed => l10n.importStatusHashFailed,
    ImportErrorCode.hashCancelled => null,
    ImportErrorCode.scanFailed => l10n.importStatusScanFailed,
    ImportErrorCode.persistenceFailed => l10n.importStatusPersistenceFailed,
    ImportErrorCode.unsupportedType => l10n.importStatusUnsupported,
    ImportErrorCode.folderValidationFailed => null,
    ImportErrorCode.duplicateIdentityConflict => null,
    ImportErrorCode.corrupted => l10n.importStatusCorrupted,
  };
}

String _validationMessage(AppLocalizations l10n, FolderValidationCode code) {
  return switch (code) {
    FolderValidationCode.doesNotExist => l10n.importValidationDoesNotExist,
    FolderValidationCode.notADirectory => l10n.importValidationNotADirectory,
    FolderValidationCode.notReadable => l10n.importValidationNotReadable,
    FolderValidationCode.isProtectedRoot =>
      l10n.importValidationIsProtectedRoot,
    FolderValidationCode.insideProtectedRoot =>
      l10n.importValidationInsideProtectedRoot,
    FolderValidationCode.containsProtectedRoot =>
      l10n.importValidationContainsProtectedRoot,
    FolderValidationCode.valid => l10n.importFailedGenericBody,
  };
}
