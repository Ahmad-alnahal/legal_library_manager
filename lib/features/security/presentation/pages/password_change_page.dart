import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../l10n/app_localizations.dart';
import '../bloc/password_change_bloc.dart';
import '../bloc/password_change_event.dart';
import '../bloc/password_change_state.dart';

/// Shown to any user whose session has [isRestrictedToPasswordChange] = true.
///
/// On success the [PasswordChangeBloc] calls [FirstLoginPasswordChange] which
/// updates the session via [SessionManager.login]; [AuthGatePage] reacts and
/// routes to [AppShellPage].
class PasswordChangePage extends StatelessWidget {
  const PasswordChangePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PasswordChangeBloc>(
      create: (_) => getIt<PasswordChangeBloc>(),
      child: const _PasswordChangeView(),
    );
  }
}

class _PasswordChangeView extends StatefulWidget {
  const _PasswordChangeView();

  @override
  State<_PasswordChangeView> createState() => _PasswordChangeViewState();
}

class _PasswordChangeViewState extends State<_PasswordChangeView> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _currentObscured = true;
  bool _newObscured = true;
  bool _confirmObscured = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    context.read<PasswordChangeBloc>().add(
          PasswordChangeSubmitted(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
            confirmPassword: _confirmController.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AppPanel(
                borderColor: AppColors.borderStrong,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.passwordChangeTitle,
                        style: text.headlineSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.passwordChangeSubtitle,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _PasswordField(
                        controller: _currentController,
                        label: l10n.passwordChangeCurrentLabel,
                        obscured: _currentObscured,
                        onToggle: () =>
                            setState(() => _currentObscured = !_currentObscured),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _PasswordField(
                        controller: _newController,
                        label: l10n.passwordChangeNewLabel,
                        hint: l10n.setupPasswordHint,
                        obscured: _newObscured,
                        onToggle: () =>
                            setState(() => _newObscured = !_newObscured),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _PasswordField(
                        controller: _confirmController,
                        label: l10n.passwordChangeConfirmLabel,
                        obscured: _confirmObscured,
                        onToggle: () =>
                            setState(() => _confirmObscured = !_confirmObscured),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(context),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      BlocBuilder<PasswordChangeBloc, PasswordChangeState>(
                        builder: (context, state) {
                          if (state is PasswordChangeError) {
                            return _ErrorBanner(
                              message: _errorMessage(state.messageKey, l10n),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      BlocBuilder<PasswordChangeBloc, PasswordChangeState>(
                        builder: (context, state) {
                          final isLoading = state is PasswordChangeInProgress;
                          return FilledButton(
                            onPressed: isLoading ? null : () => _submit(context),
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : Text(l10n.passwordChangeSubmitButton),
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
      ),
    );
  }

  String _errorMessage(String key, AppLocalizations l10n) => switch (key) {
        'passwordMismatch' => l10n.setupErrorPasswordMismatch,
        'passwordTooShort' => l10n.setupErrorPasswordTooShort,
        'incorrectCurrentPassword' => l10n.passwordChangeErrorIncorrectCurrent,
        _ => l10n.setupErrorUnexpected,
      };
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.hint,
    required this.obscured,
    required this.onToggle,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscured;
  final VoidCallback onToggle;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscured,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          onPressed: onToggle,
        ),
      ),
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
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
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF92400E),
            ),
      ),
    );
  }
}
