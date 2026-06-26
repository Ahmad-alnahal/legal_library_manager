import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../l10n/app_localizations.dart';
import '../bloc/recovery_bloc.dart';
import '../bloc/recovery_event.dart';
import '../bloc/recovery_state.dart';

/// Full-screen recovery page.
///
/// Pushed modally from [LoginPage] when the user taps the recovery link.
/// On success shows the new recovery key for one-time display with a copy
/// button and a confirmation checkbox; the "Back to login" button is disabled
/// until the checkbox is checked.
///
/// After the user taps "Back to login", [SessionManager.invalidateAll] has
/// already been called by [RedeemRecoveryKey], so [AuthGatePage] will see
/// [Unauthenticated] and route to [InitialSetupPage] (because
/// `admin.mustChangePassword == true`).
class RecoveryPage extends StatelessWidget {
  const RecoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RecoveryBloc>(
      create: (_) => getIt<RecoveryBloc>(),
      child: const _RecoveryView(),
    );
  }
}

class _RecoveryView extends StatefulWidget {
  const _RecoveryView();

  @override
  State<_RecoveryView> createState() => _RecoveryViewState();
}

class _RecoveryViewState extends State<_RecoveryView> {
  final _keyController = TextEditingController();
  bool _confirmed = false;
  bool _copied = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: BlocConsumer<RecoveryBloc, RecoveryState>(
        listener: (context, state) {
          // Nothing to do imperatively — success view is in builder.
        },
        builder: (context, state) {
          if (state is RecoverySuccess) {
            return _SuccessView(
              newRecoveryKey: state.newRecoveryKey,
              confirmed: _confirmed,
              copied: _copied,
              onCopy: () {
                Clipboard.setData(ClipboardData(text: state.newRecoveryKey));
                if (!mounted) return;
                setState(() => _copied = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.recoverySuccessCopied)),
                );
              },
              onConfirmChanged: (v) => setState(() => _confirmed = v ?? false),
              onContinue: _confirmed ? () => Navigator.of(context).pop() : null,
            );
          }

          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AppPanel(
                    borderColor: AppColors.borderStrong,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.recoveryTitle,
                            style: text.headlineSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            l10n.recoverySubtitle,
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          TextFormField(
                            controller: _keyController,
                            textDirection: TextDirection.ltr,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: l10n.recoveryKeyLabel,
                              hintText: l10n.recoveryKeyHint,
                              hintStyle: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            onFieldSubmitted: (_) => _submit(context),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          if (state is RecoveryError)
                            _ErrorBanner(message: _errorMessage(state, l10n)),
                          if (state is RecoveryError)
                            const SizedBox(height: AppSpacing.lg),
                          BlocBuilder<RecoveryBloc, RecoveryState>(
                            builder: (context, state) {
                              final isLoading = state is RecoveryInProgress;
                              return FilledButton(
                                onPressed: isLoading
                                    ? null
                                    : () => _submit(context),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.onPrimary,
                                        ),
                                      )
                                    : Text(l10n.recoverySubmitButton),
                              );
                            },
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
    );
  }

  void _submit(BuildContext context) {
    context.read<RecoveryBloc>().add(RecoverySubmitted(_keyController.text));
  }

  String _errorMessage(RecoveryError state, AppLocalizations l10n) {
    switch (state.messageKey) {
      case 'throttled':
        return l10n.recoveryErrorThrottled(state.remainingSeconds ?? 0);
      case 'invalidKey':
        return l10n.recoveryErrorInvalidKey;
      default:
        return l10n.recoveryErrorUnexpected;
    }
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.newRecoveryKey,
    required this.confirmed,
    required this.copied,
    required this.onCopy,
    required this.onConfirmChanged,
    required this.onContinue,
  });

  final String newRecoveryKey;
  final bool confirmed;
  final bool copied;
  final VoidCallback onCopy;
  final ValueChanged<bool?> onConfirmChanged;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AppPanel(
              borderColor: AppColors.borderStrong,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.recoverySuccessTitle,
                      style: text.headlineSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.recoverySuccessBody,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderStrong),
                      ),
                      child: Text(
                        newRecoveryKey,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: onCopy,
                      icon: Icon(copied ? Icons.check : Icons.copy_outlined),
                      label: Text(l10n.recoverySuccessCopyButton),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Material(
                      type: MaterialType.transparency,
                      child: CheckboxListTile(
                        value: confirmed,
                        onChanged: onConfirmChanged,
                        title: Text(
                          l10n.recoverySuccessConfirmLabel,
                          style: text.bodyMedium,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: onContinue,
                      child: Text(l10n.recoveryContinueButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFED7AA)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF92400E)),
      ),
    );
  }
}
