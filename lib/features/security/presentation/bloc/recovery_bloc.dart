import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/redeem_recovery_key.dart';
import 'recovery_event.dart';
import 'recovery_state.dart';

class RecoveryBloc extends Bloc<RecoveryEvent, RecoveryState> {
  RecoveryBloc({required this._redeemRecoveryKey})
    : super(const RecoveryInitial()) {
    on<RecoverySubmitted>(_onSubmitted);
    on<RecoveryErrorDismissed>(_onErrorDismissed);
  }

  final RedeemRecoveryKey _redeemRecoveryKey;

  Future<void> _onSubmitted(
    RecoverySubmitted event,
    Emitter<RecoveryState> emit,
  ) async {
    emit(const RecoveryInProgress());
    try {
      final newKey = await _redeemRecoveryKey.call(event.recoveryKey.trim());
      emit(RecoverySuccess(newKey));
    } on RecoveryKeyThrottledException catch (e) {
      emit(RecoveryError('throttled', remainingSeconds: e.remainingSeconds));
    } on InvalidRecoveryKeyException {
      emit(const RecoveryError('invalidKey'));
    } catch (_) {
      emit(const RecoveryError('unexpectedError'));
    }
  }

  void _onErrorDismissed(
    RecoveryErrorDismissed event,
    Emitter<RecoveryState> emit,
  ) => emit(const RecoveryInitial());
}
