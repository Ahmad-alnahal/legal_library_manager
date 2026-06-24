import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import 'account_management_page.dart';
import 'audit_log_page.dart';

/// Top-level Administration shell that presents two tabs:
/// 1. Account Management (existing [AccountManagementPage])
/// 2. Security Audit Log ([AuditLogPage])
///
/// Each tab owns its own BLoC lifecycle via [BlocProvider] inside its page.
class AdministrationPage extends StatelessWidget {
  const AdministrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          ColoredBox(
            color: AppColors.surface,
            child: TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: l10n.adminTabAccounts),
                Tab(text: l10n.adminTabAuditLog),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [AccountManagementPage(), AuditLogPage()],
            ),
          ),
        ],
      ),
    );
  }
}
