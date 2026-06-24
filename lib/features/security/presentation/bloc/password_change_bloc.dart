import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/change_own_password.dart';
import '../../application/first_login_password_change.dart';
import '../../application/set_initial_admin_password.dart'
    show WeakPasswordException;
import '../../application/unauthorized_exception.dart';
import 'password_change_event.dart';
import 'password_change_state.dart';

class PasswordChangeBloc
    extends Bloc<PasswordChangeEvent, PasswordChangeState> {
  PasswordChangeBloc({required this._firstLoginPasswordChange})
    : super(const PasswordChangeInitial()) {
    on<PasswordChangeSubmitted>(_onSubmitted);
    on<PasswordChangeErrorDismissed>(_onErrorDismissed);
  }

  final FirstLoginPasswordChange _firstLoginPasswordChange;

  Future<void> _onSubmitted(
    PasswordChangeSubmitted event,
    Emitter<PasswordChangeState> emit,
  ) async {
    if (event.newPassword != event.confirmPassword) {
      emit(const PasswordChangeError('passwordMismatch'));
      return;
    }
    emit(const PasswordChangeInProgress());
    try {
      await _firstLoginPasswordChange.call(
        currentPassword: event.currentPassword,
        newPassword: event.newPassword,
      );
      emit(const PasswordChangeSuccess());
    } on WeakPasswordException {
      emit(const PasswordChangeError('passwordTooShort'));
    } on IncorrectCurrentPasswordException {
      emit(const PasswordChangeError('incorrectCurrentPassword'));
    } on UnauthorizedException {
      emit(const PasswordChangeError('unauthorized'));
    } catch (_) {
      emit(const PasswordChangeError('unexpectedError'));
    }
  }

  void _onErrorDismissed(
    PasswordChangeErrorDismissed event,
    Emitter<PasswordChangeState> emit,
  ) => emit(const PasswordChangeInitial());
}
