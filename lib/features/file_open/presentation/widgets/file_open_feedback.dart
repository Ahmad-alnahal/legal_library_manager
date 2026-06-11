// lib/features/file_open/presentation/widgets/file_open_feedback.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/open_file_result.dart';
import '../../domain/entities/open_target.dart';
import '../bloc/file_open_bloc.dart';
import '../bloc/file_open_event.dart';
import '../bloc/file_open_state.dart';

/// Maps a terminal [FileOpenUiState] to a safe, localized Arabic message.
///
/// Returns null for non-terminal states. Only stable error codes and the open
/// target are consulted; no raw exception text, path, or command string is ever
/// surfaced.
String? fileOpenFeedbackMessage(AppLocalizations l10n, FileOpenUiState state) {
  switch (state.status) {
    case FileOpenStatus.success:
      return state.activeTarget == OpenTarget.folder
          ? l10n.fileOpenSuccessFolder
          : l10n.fileOpenSuccessFile;
    case FileOpenStatus.auditFailure:
      return state.activeTarget == OpenTarget.folder
          ? l10n.fileOpenAuditFailureFolder
          : l10n.fileOpenAuditFailureFile;
    case FileOpenStatus.blocked:
    case FileOpenStatus.failed:
      return _errorMessage(l10n, state.errorCode);
    case FileOpenStatus.idle:
    case FileOpenStatus.opening:
      return null;
  }
}

String _errorMessage(AppLocalizations l10n, FileOpenError? code) =>
    switch (code) {
      FileOpenError.fileRecordNotFound => l10n.fileOpenErrorRecordNotFound,
      FileOpenError.missingPath => l10n.fileOpenErrorMissingPath,
      FileOpenError.pathNotFound => l10n.fileOpenErrorPathNotFound,
      FileOpenError.notARegularFile => l10n.fileOpenErrorNotRegularFile,
      FileOpenError.unsupportedExtension =>
        l10n.fileOpenErrorUnsupportedExtension,
      FileOpenError.permissionDenied => l10n.fileOpenErrorPermissionDenied,
      FileOpenError.noAssociatedApplication =>
        l10n.fileOpenErrorNoAssociatedApplication,
      FileOpenError.osLaunchFailed => l10n.fileOpenErrorOsLaunchFailed,
      FileOpenError.eventPersistenceFailed => l10n.fileOpenErrorOsLaunchFailed,
      FileOpenError.unhealthyFile => l10n.fileOpenErrorUnhealthyFile,
      null => l10n.fileOpenErrorOsLaunchFailed,
    };

/// Wraps [child] with a single listener that shows one SnackBar per safe-open
/// result and then returns the controller to idle.
///
/// Placing one of these high in a page lets every [OpenActions] on that page
/// share consistent feedback without duplicate or stale SnackBars: the listener
/// fires only on the transition into a terminal status, and immediately
/// dispatches [FileOpenFeedbackHandled] so the same result cannot fire again on
/// a later rebuild.
class FileOpenFeedbackListener extends StatelessWidget {
  const FileOpenFeedbackListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<FileOpenBloc, FileOpenUiState>(
      listenWhen: (previous, current) =>
          current.isTerminal && previous.status != current.status,
      listener: (context, state) {
        final l10n = AppLocalizations.of(context);
        final message = fileOpenFeedbackMessage(l10n, state);
        if (message != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
        context.read<FileOpenBloc>().add(const FileOpenFeedbackHandled());
      },
      child: child,
    );
  }
}
