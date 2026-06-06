import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/app_section.dart';

part 'navigation_event.dart';
part 'navigation_state.dart';

/// Coordinates which primary section the desktop shell is showing.
///
/// Holds no business logic — it only tracks the selected [AppSection].
class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  NavigationBloc() : super(const NavigationState()) {
    on<NavigationSectionSelected>(_onSectionSelected);
  }

  void _onSectionSelected(
    NavigationSectionSelected event,
    Emitter<NavigationState> emit,
  ) {
    emit(state.copyWith(section: event.section));
  }
}
