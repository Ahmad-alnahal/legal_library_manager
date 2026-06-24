import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../l10n/app_localizations.dart';
import '../bloc/login_bloc.dart';
import '../bloc/login_event.dart';
import '../bloc/login_state.dart';
import 'recovery_page.dart';

/// Arabic RTL login form.
///
/// Pumped by [AuthGatePage] when no session is active. On [LoginSuccess] the
/// [SessionManager] stream is updated; [AuthGatePage] reacts and shows the
/// shell.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginBloc>(
      create: (_) => getIt<LoginBloc>(),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordObscured = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    context.read<LoginBloc>().add(
          LoginSubmitted(
            username: _usernameController.text,
            password: _passwordController.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocListener<LoginBloc, LoginState>(
        listener: (context, state) {
          // LoginSuccess: AuthGatePage reacts to SessionManager stream — no
          // explicit navigation needed here.
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AppPanel(
                  borderColor: AppColors.borderStrong,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.loginTitle,
                            style: text.headlineSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          TextFormField(
                            controller: _usernameController,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: l10n.loginUsernameLabel,
                              border: const OutlineInputBorder(),
                            ),
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          BlocBuilder<LoginBloc, LoginState>(
                            builder: (context, state) {
                              return TextFormField(
                                controller: _passwordController,
                                obscureText: _passwordObscured,
                                textDirection: TextDirection.ltr,
                                decoration: InputDecoration(
                                  labelText: l10n.loginPasswordLabel,
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _passwordObscured
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    tooltip: _passwordObscured
                                        ? l10n.loginShowPasswordTooltip
                                        : l10n.loginHidePasswordTooltip,
                                    onPressed: () => setState(() {
                                      _passwordObscured = !_passwordObscured;
                                    }),
                                  ),
                                ),
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(context),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          BlocBuilder<LoginBloc, LoginState>(
                            builder: (context, state) {
                              return _buildErrorBanner(context, state, l10n);
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          BlocBuilder<LoginBloc, LoginState>(
                            builder: (context, state) {
                              final isLoading = state is LoginInProgress;
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
                                    : Text(l10n.loginSubmitButton),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Center(
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const RecoveryPage(),
                                  ),
                                );
                              },
                              child: Text(
                                l10n.loginRecoveryLinkButton,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    LoginState state,
    AppLocalizations l10n,
  ) {
    if (state is LoginInvalidCredentials) {
      return _ErrorBanner(message: l10n.loginErrorInvalidCredentials);
    }
    if (state is LoginAccountSuspended) {
      return _ErrorBanner(message: l10n.loginErrorAccountSuspended);
    }
    if (state is LoginDelayed) {
      return _ErrorBanner(
        message: l10n.loginErrorDelay(state.remainingSeconds),
      );
    }
    return const SizedBox.shrink();
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
