import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../l10n/app_localizations.dart';
import '../bloc/initial_setup_bloc.dart';
import '../bloc/initial_setup_event.dart';
import '../bloc/initial_setup_state.dart';

/// First-run admin password setup.
///
/// Shown by [AuthGatePage] when [Account.mustChangePassword] is true and no
/// session exists. The page walks through two steps:
///
/// 1. Set a new admin password (with confirmation).
/// 2. Display the generated recovery key and require acknowledgement.
///
/// [onSetupComplete] is called after the user confirms they have saved the
/// recovery key, allowing [AuthGatePage] to proceed to [LoginPage].
class InitialSetupPage extends StatelessWidget {
  const InitialSetupPage({super.key, required this.onSetupComplete});

  final VoidCallback onSetupComplete;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<InitialSetupBloc>(
      create: (_) => getIt<InitialSetupBloc>(),
      child: _InitialSetupView(onSetupComplete: onSetupComplete),
    );
  }
}

class _InitialSetupView extends StatefulWidget {
  const _InitialSetupView({required this.onSetupComplete});

  final VoidCallback onSetupComplete;

  @override
  State<_InitialSetupView> createState() => _InitialSetupViewState();
}

class _InitialSetupViewState extends State<_InitialSetupView> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _passwordObscured = true;
  bool _confirmObscured = true;
  bool _keySaved = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<InitialSetupBloc, InitialSetupState>(
        listener: (context, state) {
          if (state is SetupComplete) {
            widget.onSetupComplete();
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AppPanel(
                    borderColor: AppColors.borderStrong,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding),
                      child: state is SetupPasswordSet
                          ? _RecoveryKeyStep(
                              recoveryKey: state.recoveryKey,
                              keySaved: _keySaved,
                              onKeySavedChanged: (v) =>
                                  setState(() => _keySaved = v ?? false),
                              onConfirm: () => context
                                  .read<InitialSetupBloc>()
                                  .add(const SetupKeyConfirmed()),
                              l10n: l10n,
                              text: text,
                            )
                          : _PasswordStep(
                              passwordController: _passwordController,
                              confirmController: _confirmController,
                              passwordObscured: _passwordObscured,
                              confirmObscured: _confirmObscured,
                              onTogglePassword: () => setState(
                                () => _passwordObscured = !_passwordObscured,
                              ),
                              onToggleConfirm: () => setState(
                                () => _confirmObscured = !_confirmObscured,
                              ),
                              onSubmit: () =>
                                  context.read<InitialSetupBloc>().add(
                                    SetupPasswordSubmitted(
                                      password: _passwordController.text,
                                      confirmPassword: _confirmController.text,
                                    ),
                                  ),
                              state: state,
                              l10n: l10n,
                              text: text,
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
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    required this.passwordController,
    required this.confirmController,
    required this.passwordObscured,
    required this.confirmObscured,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onSubmit,
    required this.state,
    required this.l10n,
    required this.text,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool passwordObscured;
  final bool confirmObscured;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;
  final InitialSetupState state;
  final AppLocalizations l10n;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final isLoading = state is SetupInProgress;
    String? errorMessage;
    if (state is SetupError) {
      final code = (state as SetupError).message;
      errorMessage = switch (code) {
        'passwordMismatch' => l10n.setupErrorPasswordMismatch,
        'passwordTooShort' => l10n.setupErrorPasswordTooShort,
        _ => l10n.setupErrorUnexpected,
      };
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.setupTitle,
          style: text.headlineSmall?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.setupSubtitle, style: text.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: passwordController,
          obscureText: passwordObscured,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: l10n.setupPasswordLabel,
            helperText: l10n.setupPasswordHint,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                passwordObscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: passwordObscured
                  ? l10n.loginShowPasswordTooltip
                  : l10n.loginHidePasswordTooltip,
              onPressed: onTogglePassword,
            ),
          ),
          textInputAction: TextInputAction.next,
          autofocus: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: confirmController,
          obscureText: confirmObscured,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: l10n.setupConfirmPasswordLabel,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                confirmObscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: confirmObscured
                  ? l10n.loginShowPasswordTooltip
                  : l10n.loginHidePasswordTooltip,
              onPressed: onToggleConfirm,
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _ErrorBanner(message: errorMessage),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: isLoading ? null : onSubmit,
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : Text(l10n.setupSubmitButton),
        ),
      ],
    );
  }
}

class _RecoveryKeyStep extends StatelessWidget {
  const _RecoveryKeyStep({
    required this.recoveryKey,
    required this.keySaved,
    required this.onKeySavedChanged,
    required this.onConfirm,
    required this.l10n,
    required this.text,
  });

  final String recoveryKey;
  final bool keySaved;
  final ValueChanged<bool?> onKeySavedChanged;
  final VoidCallback onConfirm;
  final AppLocalizations l10n;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.setupRecoveryKeyTitle,
          style: text.headlineSmall?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.setupRecoveryKeyBody, style: text.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              SelectableText(
                recoveryKey,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: Text(l10n.setupRecoveryKeyCopyButton),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: recoveryKey));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.setupRecoveryKeyCopied)),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CheckboxListTile(
          value: keySaved,
          onChanged: onKeySavedChanged,
          title: Text(l10n.setupRecoveryKeyConfirmLabel),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: keySaved ? onConfirm : null,
          child: Text(l10n.setupContinueButton),
        ),
      ],
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
