part of 'navigation_bloc.dart';

/// Immutable state for the shell navigation: which section is visible.
class NavigationState extends Equatable {
  const NavigationState({this.section = AppSection.dashboard});

  final AppSection section;

  NavigationState copyWith({AppSection? section}) =>
      NavigationState(section: section ?? this.section);

  @override
  List<Object?> get props => [section];
}
