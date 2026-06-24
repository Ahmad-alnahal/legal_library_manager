import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/create_operator_account.dart';
import '../../application/issue_temporary_password.dart';
import '../../application/session_manager.dart';
import '../../application/set_initial_admin_password.dart'
    show WeakPasswordException;
import '../../application/step_up_required_exception.dart';
import '../../application/unauthorized_exception.dart';
import '../../application/update_operator_account.dart';
import '../../domain/entities/account_status.dart';
import '../../domain/repositories/account_repository.dart';
import 'account_management_event.dart';
import 'account_management_state.dart';

class AccountManagementBloc
    extends Bloc<AccountManagementEvent, AccountManagementState> {
  AccountManagementBloc({
    required this._accounts,
    required this._createOperator,
    required this._updateOperator,
    required this._issueTempPassword,
    required this._sessionManager,
  }) : super(const AccountManagementInitial()) {
    on<AccountManagementLoadRequested>(_onLoadRequested);
    on<AccountManagementCreateOperator>(_onCreateOperator);
    on<AccountManagementSuspend>(_onSuspend);
    on<AccountManagementReactivate>(_onReactivate);
    on<AccountManagementIssueTempPassword>(_onIssueTempPassword);
    on<AccountManagementErrorDismissed>(_onErrorDismissed);
  }

  final AccountRepository _accounts;
  final CreateOperatorAccount _createOperator;
  final UpdateOperatorAccount _updateOperator;
  final IssueTemporaryPassword _issueTempPassword;
  final SessionManager _sessionManager;

  String get _actorId => _sessionManager.currentSession?.accountId ?? 'unknown';

  Future<void> _onLoadRequested(
    AccountManagementLoadRequested event,
    Emitter<AccountManagementState> emit,
  ) async {
    emit(const AccountManagementLoading());
    try {
      final operators = await _accounts.listOperators();
      final admin = await _accounts.findById('admin');
      emit(AccountManagementLoaded(operators: operators, admin: admin));
    } catch (_) {
      emit(
        const AccountManagementError(
          messageKey: 'unexpectedError',
          operators: [],
        ),
      );
    }
  }

  Future<void> _onCreateOperator(
    AccountManagementCreateOperator event,
    Emitter<AccountManagementState> emit,
  ) async {
    final current = state;
    if (current is! AccountManagementLoaded) return;
    emit(
      AccountManagementOperating(
        operators: current.operators,
        admin: current.admin,
      ),
    );
    try {
      await _createOperator.call(
        username: event.username,
        displayName: event.displayName,
        password: event.temporaryPassword,
        createdById: _actorId,
      );
      final operators = await _accounts.listOperators();
      emit(AccountManagementLoaded(operators: operators, admin: current.admin));
    } on UnauthorizedException {
      emit(
        AccountManagementError(
          messageKey: 'unauthorized',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } on StepUpRequiredException {
      emit(
        AccountManagementError(
          messageKey: 'stepUpRequired',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } on DuplicateUsernameException {
      emit(
        AccountManagementError(
          messageKey: 'duplicateUsername',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } on WeakPasswordException {
      emit(
        AccountManagementError(
          messageKey: 'passwordTooShort',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } catch (_) {
      emit(
        AccountManagementError(
          messageKey: 'unexpectedError',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    }
  }

  Future<void> _onSuspend(
    AccountManagementSuspend event,
    Emitter<AccountManagementState> emit,
  ) async {
    await _updateStatus(event.operatorId, AccountStatus.suspended, emit);
  }

  Future<void> _onReactivate(
    AccountManagementReactivate event,
    Emitter<AccountManagementState> emit,
  ) async {
    await _updateStatus(event.operatorId, AccountStatus.active, emit);
  }

  Future<void> _updateStatus(
    String operatorId,
    AccountStatus status,
    Emitter<AccountManagementState> emit,
  ) async {
    final current = state;
    if (current is! AccountManagementLoaded) return;
    emit(
      AccountManagementOperating(
        operators: current.operators,
        admin: current.admin,
      ),
    );
    try {
      await _updateOperator.call(
        operatorId: operatorId,
        status: status,
        actorAccountId: _actorId,
      );
      final operators = await _accounts.listOperators();
      emit(AccountManagementLoaded(operators: operators, admin: current.admin));
    } on UnauthorizedException {
      emit(
        AccountManagementError(
          messageKey: 'unauthorized',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } on StepUpRequiredException {
      emit(
        AccountManagementError(
          messageKey: 'stepUpRequired',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } catch (_) {
      emit(
        AccountManagementError(
          messageKey: 'unexpectedError',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    }
  }

  Future<void> _onIssueTempPassword(
    AccountManagementIssueTempPassword event,
    Emitter<AccountManagementState> emit,
  ) async {
    final current = state;
    if (current is! AccountManagementLoaded) return;
    emit(
      AccountManagementOperating(
        operators: current.operators,
        admin: current.admin,
      ),
    );
    try {
      await _issueTempPassword.call(
        operatorId: event.operatorId,
        temporaryPassword: event.temporaryPassword,
        actorAccountId: _actorId,
      );
      final operators = await _accounts.listOperators();
      emit(AccountManagementLoaded(operators: operators, admin: current.admin));
    } on UnauthorizedException {
      emit(
        AccountManagementError(
          messageKey: 'unauthorized',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } on StepUpRequiredException {
      emit(
        AccountManagementError(
          messageKey: 'stepUpRequired',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } on WeakPasswordException {
      emit(
        AccountManagementError(
          messageKey: 'passwordTooShort',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    } catch (_) {
      emit(
        AccountManagementError(
          messageKey: 'unexpectedError',
          operators: current.operators,
          admin: current.admin,
        ),
      );
    }
  }

  void _onErrorDismissed(
    AccountManagementErrorDismissed event,
    Emitter<AccountManagementState> emit,
  ) {
    final current = state;
    if (current is AccountManagementError) {
      emit(
        AccountManagementLoaded(
          operators: current.operators,
          admin: current.admin,
        ),
      );
    }
  }
}
