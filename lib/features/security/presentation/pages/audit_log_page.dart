import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/security_audit_event.dart';
import '../bloc/audit_log_bloc.dart';
import '../bloc/audit_log_event.dart';
import '../bloc/audit_log_state.dart';

/// Admin-only paginated view of the append-only security audit log.
///
/// Events are displayed newest-first in pages of 25. A "Load more" button
/// appends the next page. No filtering or deletion controls are offered; the
/// log is permanent by design.
class AuditLogPage extends StatelessWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuditLogBloc>(
      create: (_) => getIt<AuditLogBloc>()..add(const AuditLogLoadRequested()),
      child: const _AuditLogView(),
    );
  }
}

class _AuditLogView extends StatelessWidget {
  const _AuditLogView();

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
              Text(
                l10n.auditLogTitle,
                style: text.titleLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.auditLogSubtitle,
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: BlocBuilder<AuditLogBloc, AuditLogState>(
                  builder: (context, state) {
                    if (state is AuditLogLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is AuditLogError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.auditLogErrorBody,
                              style: text.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            OutlinedButton(
                              onPressed: () => context.read<AuditLogBloc>().add(
                                const AuditLogLoadRequested(),
                              ),
                              child: Text(l10n.auditLogRetry),
                            ),
                          ],
                        ),
                      );
                    }

                    final events = switch (state) {
                      AuditLogLoaded(:final events) => events,
                      AuditLogLoadingMore(:final events) => events,
                      _ => const <SecurityAuditEvent>[],
                    };
                    final isLoadingMore = state is AuditLogLoadingMore;
                    final hasMore = state is AuditLogLoaded && state.hasMore;

                    if (events.isEmpty) {
                      return Center(
                        child: Text(
                          l10n.auditLogEmpty,
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount:
                          events.length + (hasMore || isLoadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index == events.length) {
                          if (isLoadingMore) {
                            return const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                            child: Center(
                              child: OutlinedButton(
                                onPressed: () => context
                                    .read<AuditLogBloc>()
                                    .add(const AuditLogLoadMoreRequested()),
                                child: Text(l10n.auditLogLoadMore),
                              ),
                            ),
                          );
                        }
                        return _EventRow(event: events[index], l10n: l10n);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.l10n});

  final SecurityAuditEvent event;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dt = event.createdAt.toLocal();
    final formatted =
        '${dt.year}/${_p(dt.month)}/${_p(dt.day)}  ${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              formatted,
              style: text.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: Text(
              _eventLabel(event.eventTypeKey, l10n),
              style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: Text(
              _actorLabel(event, l10n),
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  String _eventLabel(String key, AppLocalizations l10n) {
    return switch (key) {
      'admin_bootstrapped' => l10n.auditEventAdminBootstrapped,
      'password_changed' => l10n.auditEventPasswordChanged,
      'login_success' => l10n.auditEventLoginSuccess,
      'login_failed' => l10n.auditEventLoginFailed,
      'account_created' => l10n.auditEventAccountCreated,
      'account_suspended' => l10n.auditEventAccountSuspended,
      'account_reactivated' => l10n.auditEventAccountReactivated,
      'temp_password_issued' => l10n.auditEventTempPasswordIssued,
      'account_auto_suspended' => l10n.auditEventAccountAutoSuspended,
      'recovery_key_redeemed' => l10n.auditEventRecoveryKeyRedeemed,
      'step_up_granted' => l10n.auditEventStepUpGranted,
      'step_up_denied' => l10n.auditEventStepUpDenied,
      _ => l10n.auditEventUnknown,
    };
  }

  String _actorLabel(SecurityAuditEvent event, AppLocalizations l10n) {
    final actor = event.actorAccountId;
    if (actor == null) return l10n.auditActorSystem;
    if (actor == 'admin') return l10n.auditActorAdmin;
    return actor;
  }
}
