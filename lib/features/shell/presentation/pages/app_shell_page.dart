import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../categories/presentation/pages/category_management_page.dart';
import '../../../dashboard/presentation/pages/dashboard_page.dart';
import '../../../documents/presentation/pages/document_review_page.dart';
import '../../../documents/presentation/pages/documents_page.dart';
import '../../../duplicates/presentation/pages/duplicate_review_page.dart';
import '../../../import/presentation/pages/import_page.dart';
import '../../../security/application/session_manager.dart';
import '../../../security/domain/entities/account_role.dart';
import '../../../security/presentation/pages/administration_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../domain/entities/app_section.dart';
import '../bloc/navigation_bloc.dart';
import '../widgets/side_navigation.dart';

/// Root desktop shell: right-side navigation plus the active section's page.
class AppShellPage extends StatelessWidget {
  const AppShellPage({super.key});

  /// Below this width the navigation rail collapses to icons only.
  static const double _compactBreakpoint = 1160;

  @override
  Widget build(BuildContext context) {
    final sessionManager = getIt<SessionManager>();
    return BlocProvider<NavigationBloc>(
      create: (_) => getIt<NavigationBloc>(),
      child: Listener(
        // Resets the admin 30-minute inactivity timer on every pointer-down
        // and scroll event so the session expires after 30 minutes of genuine
        // inactivity, not 30 minutes after login.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => sessionManager.resetAdminInactivityTimer(),
        onPointerSignal: (_) => sessionManager.resetAdminInactivityTimer(),
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool extended =
                    constraints.maxWidth >= _compactBreakpoint;
                return BlocBuilder<NavigationBloc, NavigationState>(
                  builder: (context, state) {
                    final bool isAdmin =
                        sessionManager.currentSession?.role ==
                        AccountRole.admin;
                    return Row(
                      children: [
                        // First child renders on the right under RTL.
                        SideNavigation(
                          selected: state.section,
                          extended: extended,
                          showAdministration: isAdmin,
                          onSelected: (section) => context
                              .read<NavigationBloc>()
                              .add(NavigationSectionSelected(section)),
                        ),
                        Expanded(child: _SectionView(section: state.section)),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      AppSection.dashboard => const DashboardPage(),
      AppSection.import => const ImportPage(),
      AppSection.documents => const DocumentsPage(),
      AppSection.review => const DocumentReviewPage(),
      AppSection.categories => const CategoryManagementPage(),
      AppSection.duplicates => const DuplicateReviewPage(),
      AppSection.settings => const SettingsPage(),
      AppSection.administration => const AdministrationPage(),
    };
  }
}
