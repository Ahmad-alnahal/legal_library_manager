import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/account_status.dart';
import '../bloc/account_management_bloc.dart';
import '../bloc/account_management_event.dart';
import '../bloc/account_management_state.dart';

/// Admin-only page for viewing and managing operator accounts.
///
/// The admin account is shown read-only at the top. Operators are listed below
/// with actions to suspend, reactivate, and issue temporary passwords.
class AccountManagementPage extends StatelessWidget {
  const AccountManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AccountManagementBloc>(
      create: (_) => getIt<AccountManagementBloc>()
        ..add(const AccountManagementLoadRequested()),
      child: const _AccountManagementView(),
    );
  }
}

class _AccountManagementView extends StatelessWidget {
  const _AccountManagementView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.accountManagementTitle,
                      style: text.headlineMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  BlocBuilder<AccountManagementBloc, AccountManagementState>(
                    builder: (context, state) {
                      final canCreate =
                          state is AccountManagementLoaded ||
                          state is AccountManagementError;
                      return FilledButton.icon(
                        onPressed: canCreate
                            ? () => _showCreateDialog(context, l10n)
                            : null,
                        icon: const Icon(Icons.person_add_outlined, size: 18),
                        label: Text(l10n.accountManagementCreateButton),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              BlocBuilder<AccountManagementBloc, AccountManagementState>(
                builder: (context, state) {
                  return switch (state) {
                    AccountManagementInitial() ||
                    AccountManagementLoading() =>
                      const Center(child: CircularProgressIndicator()),
                    AccountManagementError(:final messageKey) =>
                      _ErrorBanner(messageKey: messageKey),
                    AccountManagementLoaded(:final operators, :final admin) ||
                    AccountManagementOperating(
                      :final operators,
                      :final admin
                    ) => _AccountList(
                        operators: operators,
                        admin: admin,
                        isOperating: state is AccountManagementOperating,
                      ),
                  };
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _CreateOperatorDialog(
        l10n: l10n,
        onConfirm: (username, displayName, password) {
          context.read<AccountManagementBloc>().add(
                AccountManagementCreateOperator(
                  username: username,
                  displayName: displayName,
                  temporaryPassword: password,
                ),
              );
        },
      ),
    );
  }
}

class _AccountList extends StatelessWidget {
  const _AccountList({
    required this.operators,
    required this.admin,
    required this.isOperating,
  });

  final List<Account> operators;
  final Account? admin;
  final bool isOperating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Expanded(
      child: ListView(
        children: [
          if (admin != null) ...[
            _SectionHeader(l10n.accountManagementAdminSection),
            _AdminRow(admin: admin!),
            const Divider(height: AppSpacing.xl),
            _SectionHeader(l10n.accountManagementOperatorsSection),
          ],
          if (operators.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Text(
                  l10n.accountManagementNoOperators,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            )
          else
            for (final op in operators)
              _OperatorRow(
                operator: op,
                enabled: !isOperating,
              ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({required this.admin});
  final Account admin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: AppColors.surface,
      child: ListTile(
        leading: const Icon(Icons.shield_outlined, color: AppColors.primary),
        title: Text(
          admin.displayName,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(admin.username, style: text.bodySmall),
        trailing: _StatusChip(
          label: l10n.accountStatusActive,
          color: Colors.green,
        ),
      ),
    );
  }
}

class _OperatorRow extends StatelessWidget {
  const _OperatorRow({required this.operator, required this.enabled});
  final Account operator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final isSuspended = operator.status == AccountStatus.suspended;

    return Card(
      elevation: 0,
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(
          Icons.person_outlined,
          color:
              isSuspended ? AppColors.textSecondary : AppColors.textPrimary,
        ),
        title: Text(
          operator.displayName,
          style: text.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: isSuspended ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(operator.username, style: text.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusChip(
              label: isSuspended
                  ? l10n.accountStatusSuspended
                  : l10n.accountStatusActive,
              color: isSuspended ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: AppSpacing.sm),
            PopupMenuButton<_OperatorAction>(
              enabled: enabled,
              icon: const Icon(Icons.more_vert),
              onSelected: (action) =>
                  _handleAction(context, action, operator, l10n),
              itemBuilder: (_) => [
                if (!isSuspended)
                  PopupMenuItem(
                    value: _OperatorAction.suspend,
                    child: Text(l10n.accountActionSuspend),
                  )
                else
                  PopupMenuItem(
                    value: _OperatorAction.reactivate,
                    child: Text(l10n.accountActionReactivate),
                  ),
                PopupMenuItem(
                  value: _OperatorAction.issueTempPassword,
                  child: Text(l10n.accountActionIssueTempPassword),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(
    BuildContext context,
    _OperatorAction action,
    Account op,
    AppLocalizations l10n,
  ) {
    switch (action) {
      case _OperatorAction.suspend:
        context.read<AccountManagementBloc>().add(
              AccountManagementSuspend(op.internalId),
            );
      case _OperatorAction.reactivate:
        context.read<AccountManagementBloc>().add(
              AccountManagementReactivate(op.internalId),
            );
      case _OperatorAction.issueTempPassword:
        _showIssueTempPasswordDialog(context, op, l10n);
    }
  }

  void _showIssueTempPasswordDialog(
    BuildContext context,
    Account op,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _IssueTempPasswordDialog(
        operatorName: op.displayName,
        l10n: l10n,
        onConfirm: (password) {
          context.read<AccountManagementBloc>().add(
                AccountManagementIssueTempPassword(
                  operatorId: op.internalId,
                  temporaryPassword: password,
                ),
              );
        },
      ),
    );
  }
}

enum _OperatorAction { suspend, reactivate, issueTempPassword }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.messageKey});
  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = switch (messageKey) {
      'duplicateUsername' => l10n.accountManagementErrorDuplicateUsername,
      'passwordTooShort' => l10n.setupErrorPasswordTooShort,
      _ => l10n.setupErrorUnexpected,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFED7AA)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_outlined, color: Color(0xFF92400E)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF92400E),
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: const Color(0xFF92400E),
            onPressed: () => context
                .read<AccountManagementBloc>()
                .add(const AccountManagementErrorDismissed()),
          ),
        ],
      ),
    );
  }
}

class _CreateOperatorDialog extends StatefulWidget {
  const _CreateOperatorDialog({
    required this.l10n,
    required this.onConfirm,
  });
  final AppLocalizations l10n;
  final void Function(String username, String displayName, String password)
      onConfirm;

  @override
  State<_CreateOperatorDialog> createState() => _CreateOperatorDialogState();
}

class _CreateOperatorDialogState extends State<_CreateOperatorDialog> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordObscured = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AlertDialog(
      title: Text(l10n.accountManagementCreateDialogTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: l10n.accountManagementDisplayNameLabel,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _usernameController,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: l10n.loginUsernameLabel,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _passwordController,
              obscureText: _passwordObscured,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: l10n.accountManagementTempPasswordLabel,
                hintText: l10n.setupPasswordHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordObscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _passwordObscured = !_passwordObscured),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.accountManagementCancelButton),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onConfirm(
              _usernameController.text.trim(),
              _displayNameController.text.trim(),
              _passwordController.text,
            );
          },
          child: Text(l10n.accountManagementCreateConfirmButton),
        ),
      ],
    );
  }
}

class _IssueTempPasswordDialog extends StatefulWidget {
  const _IssueTempPasswordDialog({
    required this.operatorName,
    required this.l10n,
    required this.onConfirm,
  });
  final String operatorName;
  final AppLocalizations l10n;
  final void Function(String password) onConfirm;

  @override
  State<_IssueTempPasswordDialog> createState() =>
      _IssueTempPasswordDialogState();
}

class _IssueTempPasswordDialogState extends State<_IssueTempPasswordDialog> {
  final _passwordController = TextEditingController();
  bool _passwordObscured = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AlertDialog(
      title: Text(l10n.accountManagementIssueTempPasswordTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.accountManagementIssueTempPasswordBody(widget.operatorName),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _passwordController,
              obscureText: _passwordObscured,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: l10n.accountManagementTempPasswordLabel,
                hintText: l10n.setupPasswordHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordObscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _passwordObscured = !_passwordObscured),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.accountManagementCancelButton),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onConfirm(_passwordController.text);
          },
          child: Text(l10n.accountManagementConfirmButton),
        ),
      ],
    );
  }
}
