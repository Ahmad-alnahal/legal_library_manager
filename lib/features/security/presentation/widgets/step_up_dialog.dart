// lib/features/security/presentation/widgets/step_up_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/step_up_manager.dart';
import '../bloc/step_up_bloc.dart';
import '../bloc/step_up_event.dart';
import '../bloc/step_up_state.dart';

/// Shows a step-up authentication dialog and invokes [onSuccess] if the
/// administrator's password is verified successfully. If the current step-up
/// approval is already active the dialog is skipped and [onSuccess] is called
/// immediately.
///
/// Usage:
/// ```dart
/// await requireStepUp(context, () {
///   // perform sensitive action
/// });
/// ```
Future<void> requireStepUp(BuildContext context, VoidCallback onSuccess) async {
  final stepUpManager = getIt<StepUpManager>();
  if (stepUpManager.isApproved) {
    onSuccess();
    return;
  }
  if (!context.mounted) return;
  final approved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider<StepUpBloc>(
      create: (_) => getIt<StepUpBloc>(),
      child: const _StepUpDialogContent(),
    ),
  );
  if (approved == true && context.mounted) {
    onSuccess();
  }
}

class _StepUpDialogContent extends StatefulWidget {
  const _StepUpDialogContent();

  @override
  State<_StepUpDialogContent> createState() => _StepUpDialogContentState();
}

class _StepUpDialogContentState extends State<_StepUpDialogContent> {
  final _passwordController = TextEditingController();
  bool _obscured = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocListener<StepUpBloc, StepUpState>(
      listener: (context, state) {
        if (state is StepUpSuccess) {
          Navigator.of(context).pop(true);
        }
      },
      child: BlocBuilder<StepUpBloc, StepUpState>(
        builder: (context, state) {
          final isVerifying = state is StepUpVerifying;
          return AlertDialog(
            title: Text(l10n.stepUpDialogTitle),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.stepUpDialogSubtitle),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscured,
                    textDirection: TextDirection.ltr,
                    enabled: !isVerifying,
                    decoration: InputDecoration(
                      labelText: l10n.stepUpPasswordLabel,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscured
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscured = !_obscured),
                      ),
                    ),
                    onSubmitted: isVerifying ? null : (_) => _submit(context),
                  ),
                  if (state is StepUpError) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      state.messageKey == 'wrongPassword'
                          ? l10n.stepUpErrorWrongPassword
                          : l10n.stepUpErrorUnexpected,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isVerifying
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(l10n.stepUpCancelButton),
              ),
              FilledButton(
                onPressed: isVerifying ? null : () => _submit(context),
                child: isVerifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.stepUpVerifyButton),
              ),
            ],
          );
        },
      ),
    );
  }

  void _submit(BuildContext context) {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    context.read<StepUpBloc>().add(StepUpPasswordSubmitted(password));
  }
}
