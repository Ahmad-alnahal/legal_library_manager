// test/features/security/presentation/step_up_bloc_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/security/application/unauthorized_exception.dart';
import 'package:legal_library_manager/features/security/application/verify_admin_step_up.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/step_up_bloc.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/step_up_event.dart';
import 'package:legal_library_manager/features/security/presentation/bloc/step_up_state.dart';

/// Fake implementation of [VerifyAdminStepUp] that lets tests control
/// the returned result without any database or password hasher.
class _FakeVerifyAdminStepUp implements VerifyAdminStepUp {
  _FakeVerifyAdminStepUp(this._respond);

  final Future<StepUpVerifyResult> Function(String password) _respond;

  @override
  Future<StepUpVerifyResult> call(String password) => _respond(password);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

StepUpBloc _makeBloc(Future<StepUpVerifyResult> Function(String) respond) =>
    StepUpBloc(verifyAdminStepUp: _FakeVerifyAdminStepUp(respond));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('StepUpBloc', () {
    test('initial state is StepUpInitial', () {
      final bloc = _makeBloc((_) async => const StepUpVerifySuccess());
      expect(bloc.state, isA<StepUpInitial>());
      bloc.close();
    });

    test(
      'StepUpPasswordSubmitted emits Verifying then Success on correct password',
      () async {
        final bloc = _makeBloc((_) async => const StepUpVerifySuccess());

        expect(
          bloc.stream,
          emitsInOrder([isA<StepUpVerifying>(), isA<StepUpSuccess>()]),
        );

        bloc.add(const StepUpPasswordSubmitted('correct'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await bloc.close();
      },
    );

    test('StepUpPasswordSubmitted emits Verifying then Error(wrongPassword) '
        'on wrong password', () async {
      final bloc = _makeBloc((_) async => const StepUpVerifyWrongPassword());

      expect(
        bloc.stream,
        emitsInOrder([
          isA<StepUpVerifying>(),
          predicate<StepUpState>(
            (s) => s is StepUpError && s.messageKey == 'wrongPassword',
          ),
        ]),
      );

      bloc.add(const StepUpPasswordSubmitted('wrong'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await bloc.close();
    });

    test(
      'emits Error(wrongPassword) when use case throws UnauthorizedException',
      () async {
        final bloc = _makeBloc(
          (_) async => throw const UnauthorizedException('no session'),
        );

        expect(
          bloc.stream,
          emitsInOrder([
            isA<StepUpVerifying>(),
            predicate<StepUpState>(
              (s) => s is StepUpError && s.messageKey == 'wrongPassword',
            ),
          ]),
        );

        bloc.add(const StepUpPasswordSubmitted('anything'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await bloc.close();
      },
    );

    test(
      'emits Error(unexpected) when use case throws an unexpected exception',
      () async {
        final bloc = _makeBloc(
          (_) async => throw Exception('something went wrong'),
        );

        expect(
          bloc.stream,
          emitsInOrder([
            isA<StepUpVerifying>(),
            predicate<StepUpState>(
              (s) => s is StepUpError && s.messageKey == 'unexpected',
            ),
          ]),
        );

        bloc.add(const StepUpPasswordSubmitted('anything'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await bloc.close();
      },
    );

    test(
      'StepUpErrorDismissed transitions StepUpError back to StepUpInitial',
      () async {
        final bloc = _makeBloc((_) async => const StepUpVerifyWrongPassword());

        bloc.add(const StepUpPasswordSubmitted('wrong'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(bloc.state, isA<StepUpError>());

        expect(bloc.stream, emits(isA<StepUpInitial>()));
        bloc.add(const StepUpErrorDismissed());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await bloc.close();
      },
    );
  });
}
