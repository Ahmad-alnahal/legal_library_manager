import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/set_initial_admin_password.dart';
import 'initial_setup_event.dart';
import 'initial_setup_state.dart';

class InitialSetupBloc extends Bloc<InitialSetupEvent, InitialSetupState> {
  InitialSetupBloc({required this._setInitialAdminPassword})
      : super(const SetupInitial()) {
    on<SetupPasswordSubmitted>(_onPasswordSubmitted);
    on<SetupKeyConfirmed>(_onKeyConfirmed);
  }

  final SetInitialAdminPassword _setInitialAdminPassword;

  Future<void> _onPasswordSubmitted(
    SetupPasswordSubmitted event,
    Emitter<InitialSetupState> emit,
  ) async {
    if (event.password != event.confirmPassword) {
      emit(const SetupError('passwordMismatch'));
      return;
    }
    if (event.password.length < kMinPasswordLength) {
      emit(const SetupError('passwordTooShort'));
      return;
    }
    emit(const SetupInProgress());
    try {
      final recoveryKey = await _setInitialAdminPassword(event.password);
      emit(SetupPasswordSet(recoveryKey));
    } catch (_) {
      emit(const SetupError('unexpectedError'));
    }
  }

  void _onKeyConfirmed(
    SetupKeyConfirmed event,
    Emitter<InitialSetupState> emit,
  ) {
    emit(const SetupComplete());
  }
}
