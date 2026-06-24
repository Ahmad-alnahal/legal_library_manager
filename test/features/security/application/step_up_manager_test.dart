// test/features/security/application/step_up_manager_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';

void main() {
  group('StepUpManager', () {
    test('isApproved is false initially', () {
      final manager = StepUpManager();
      expect(manager.isApproved, isFalse);
    });

    test('grant() sets isApproved to true', () {
      final manager = StepUpManager();
      manager.grant();
      expect(manager.isApproved, isTrue);
    });

    test('revoke() clears approval immediately', () {
      final manager = StepUpManager();
      manager.grant();
      manager.revoke();
      expect(manager.isApproved, isFalse);
    });

    test('grant() can be called repeatedly without error', () {
      final manager = StepUpManager();
      manager.grant();
      manager.grant();
      expect(manager.isApproved, isTrue);
    });

    test('revoke() on already-revoked manager is safe', () {
      final manager = StepUpManager();
      manager.revoke();
      expect(manager.isApproved, isFalse);
    });

    test('dispose() clears approval', () {
      final manager = StepUpManager();
      manager.grant();
      manager.dispose();
      expect(manager.isApproved, isFalse);
    });

    test('approval expires after the configured window', () async {
      final manager = StepUpManager(
        stepUpWindow: const Duration(milliseconds: 50),
      );
      manager.grant();
      expect(manager.isApproved, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(manager.isApproved, isFalse);
    });

    test('calling grant() resets the expiry timer', () async {
      final manager = StepUpManager(
        stepUpWindow: const Duration(milliseconds: 100),
      );
      manager.grant();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Re-grant: should restart the full 100ms window.
      manager.grant();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // 60ms after second grant — still within the new window.
      expect(manager.isApproved, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // 120ms after second grant — expired.
      expect(manager.isApproved, isFalse);
    });
  });
}
