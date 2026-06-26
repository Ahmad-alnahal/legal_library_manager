import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/security/data/services/argon2id_password_hasher.dart';

// Use minimal parameters so tests finish in milliseconds.
const _hasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);

void main() {
  group('Argon2idPasswordHasher', () {
    test('hash returns a valid PHC-format string', () async {
      final result = await _hasher.hash('correct-horse-battery');
      expect(result, startsWith(r'$argon2id$v=19$'));
    });

    test('hash encodes memory, iteration, and lane parameters', () async {
      const h = Argon2idPasswordHasher(memoryKib: 512, iterations: 2, lanes: 1);
      final result = await h.hash('pw');
      expect(result, contains('m=512,t=2,p=1'));
    });

    test('two hash calls produce different strings (unique salts)', () async {
      final a = await _hasher.hash('same-password');
      final b = await _hasher.hash('same-password');
      expect(a, isNot(equals(b)));
    });

    test('verify returns true for the correct password', () async {
      final stored = await _hasher.hash('hunter2');
      expect(await _hasher.verify('hunter2', stored), isTrue);
    });

    test('verify returns false for a wrong password', () async {
      final stored = await _hasher.hash('hunter2');
      expect(await _hasher.verify('wrong', stored), isFalse);
    });

    test(
      'verify returns false for an empty password against a real hash',
      () async {
        final stored = await _hasher.hash('not-empty');
        expect(await _hasher.verify('', stored), isFalse);
      },
    );

    test(
      'verify returns false for the sentinel hash regardless of password',
      () async {
        const sentinel = r'$sentinel$v=0$not-a-real-hash$';
        expect(await _hasher.verify('anything', sentinel), isFalse);
        expect(await _hasher.verify('', sentinel), isFalse);
      },
    );

    test(
      'verify returns false for a completely malformed stored hash',
      () async {
        expect(await _hasher.verify('pw', 'garbage'), isFalse);
        expect(await _hasher.verify('pw', ''), isFalse);
        expect(await _hasher.verify('pw', r'$'), isFalse);
      },
    );

    test('verify uses parameters embedded in the stored hash', () async {
      // Hash with low params; verify with a hasher configured at higher params.
      // Verification must still pass because it reads params from the string.
      const lowHasher = Argon2idPasswordHasher(memoryKib: 128, iterations: 1);
      const highHasher = Argon2idPasswordHasher(memoryKib: 256, iterations: 1);
      final stored = await lowHasher.hash('cross-param');
      expect(await highHasher.verify('cross-param', stored), isTrue);
    });

    test('PHC string contains exactly 5 dollar-sign separators', () async {
      final result = await _hasher.hash('count-dollars');
      expect('\$'.allMatches(result).length, 5);
    });
  });
}
