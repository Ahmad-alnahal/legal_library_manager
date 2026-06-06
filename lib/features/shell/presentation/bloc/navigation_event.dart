part of 'navigation_bloc.dart';

/// Events for the shell navigation.
sealed class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => const [];
}

/// Raised when the user selects a navigation destination.
class NavigationSectionSelected extends NavigationEvent {
  const NavigationSectionSelected(this.section);

  final AppSection section;

  @override
  List<Object?> get props => [section];
}
