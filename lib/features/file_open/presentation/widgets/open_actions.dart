// lib/features/file_open/presentation/widgets/open_actions.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/open_target.dart';
import '../bloc/file_open_bloc.dart';
import '../bloc/file_open_event.dart';
import '../bloc/file_open_state.dart';

/// Reusable safe-open actions for one registered source file.
///
/// Renders separate "Open File" and "Open Folder" controls that drive the
/// shared [FileOpenBloc] using only the database [fileId] — never a path. While
/// any open request is in flight both controls are disabled (preventing
/// overlapping launches) and only the clicked control shows a spinner.
///
/// Pass [showOpenFile] = false to hide the "Open File" button for non-healthy
/// files (corrupted, unreadable, missing, unknown). The "Open Folder" button is
/// always rendered so users can reach the containing directory to investigate.
///
/// A [FileOpenBloc] must be provided above this widget, and a
/// [FileOpenFeedbackListener] should wrap the page so results are reported once.
class OpenActions extends StatelessWidget {
  const OpenActions({
    super.key,
    required this.fileId,
    required this.showOpenFile,
  });

  final int fileId;
  final bool showOpenFile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<FileOpenBloc, FileOpenUiState>(
      builder: (context, state) {
        final busy = state.isBusy;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (showOpenFile)
              _ActionButton(
                key: Key('open_file_button_$fileId'),
                icon: Icons.open_in_new,
                label: l10n.fileOpenOpenFile,
                loadingLabel: l10n.fileOpenOpening,
                loading: state.isActive(fileId, OpenTarget.file),
                onPressed: busy
                    ? null
                    : () => context.read<FileOpenBloc>().add(
                        FileOpenRequested(fileId, OpenTarget.file),
                      ),
              ),
            _ActionButton(
              key: Key('open_folder_button_$fileId'),
              icon: Icons.folder_open,
              label: l10n.fileOpenOpenFolder,
              loadingLabel: l10n.fileOpenOpening,
              loading: state.isActive(fileId, OpenTarget.folder),
              onPressed: busy
                  ? null
                  : () => context.read<FileOpenBloc>().add(
                      FileOpenRequested(fileId, OpenTarget.folder),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.loadingLabel,
    required this.loading,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String loadingLabel;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget leading = loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 18);
    return Tooltip(
      message: loading ? loadingLabel : label,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: leading,
        label: Text(label),
      ),
    );
  }
}
