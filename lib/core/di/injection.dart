import 'package:get_it/get_it.dart';

import '../../features/shell/presentation/bloc/navigation_bloc.dart';

/// Global service locator.
final GetIt getIt = GetIt.instance;

/// Registers M1 dependencies.
///
/// Kept intentionally small: only the shell navigation BLoC is needed so far.
/// Data/domain services are registered here in later milestones.
void configureDependencies() {
  getIt.registerFactory<NavigationBloc>(NavigationBloc.new);
}
