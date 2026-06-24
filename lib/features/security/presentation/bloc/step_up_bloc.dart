// lib/features/security/presentation/bloc/step_up_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/unauthorized_exception.dart';
import '../../application/verify_admin_step_up.dart';
import 'step_up_event.dart';
import 'step_up_state.dart';

class StepUpBloc extends Bloc<StepUpEvent, StepUpState> {
  StepUpBloc({required this._verifyAdminStepUp}) : super(const StepUpInitial()) {
    on<StepUpPasswordSubmitted>(_onPasswordSubmitted);
    on<StepUpErrorDismissed>(_onErrorDismissed);
  }

  final VerifyAdminStepUp _verifyAdminStepUp;

  Future<void> _onPasswordSubmitted(
    StepUpPasswordSubmitted event,
    Emitter<StepUpState> emit,
  ) async {
    emit(const StepUpVerifying());
    try {
      final result = await _verifyAdminStepUp(event.password);
      if (result is StepUpVerifySuccess) {
        emit(const StepUpSuccess());
      } else {
        emit(const StepUpError('wrongPassword'));
      }
    } on UnauthorizedException {
      emit(const StepUpError('wrongPassword'));
    } catch (_) {
      emit(const StepUpError('unexpected'));
    }
  }

  void _onErrorDismissed(
    StepUpErrorDismissed event,
    Emitter<StepUpState> emit,
  ) {
    emit(const StepUpInitial());
  }
}
