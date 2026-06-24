import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/authenticate_user.dart';
import 'login_event.dart';
import 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc({required this._authenticateUser}) : super(const LoginInitial()) {
    on<LoginSubmitted>(_onSubmitted);
    on<LoginErrorDismissed>(_onErrorDismissed);
  }

  final AuthenticateUser _authenticateUser;

  Future<void> _onSubmitted(
    LoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginInProgress());
    final result = await _authenticateUser(
      username: event.username.trim(),
      password: event.password,
    );
    switch (result) {
      case AuthSuccess():
        emit(LoginSuccess(result.session));
      case AuthLoginDelayed():
        emit(LoginDelayed(result.remainingSeconds));
      case AuthInvalidCredentials():
        emit(const LoginInvalidCredentials());
      case AuthAccountSuspended():
        emit(const LoginAccountSuspended());
    }
  }

  void _onErrorDismissed(
    LoginErrorDismissed event,
    Emitter<LoginState> emit,
  ) {
    emit(const LoginInitial());
  }
}
