import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../dashboard/presentation/pages/dashboard_page.dart';
import '../../../documents/presentation/pages/documents_page.dart';
import '../../../duplicates/presentation/pages/duplicate_review_page.dart';
import '../../../import/presentation/pages/import_page.dart';
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
    return BlocProvider<NavigationBloc>(
      create: (_) => getIt<NavigationBloc>(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool extended = constraints.maxWidth >= _compactBreakpoint;
              return BlocBuilder<NavigationBloc, NavigationState>(
                builder: (context, state) {
                  return Row(
                    children: [
                      // First child renders on the right under RTL.
                      SideNavigation(
                        selected: state.section,
                        extended: extended,
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
      AppSection.duplicates => const DuplicateReviewPage(),
      AppSection.settings => const SettingsPage(),
    };
  }
}
