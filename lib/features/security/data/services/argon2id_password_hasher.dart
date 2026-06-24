// The constructor parameter names (memoryKib, iterations, lanes) differ from
// the private field names (_memoryKib, …) intentionally to keep the public API
// readable. Suppress the lint that suggests renaming the parameters.
// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:argon2/argon2.dart';

import '../../domain/services/password_hasher.dart';

// Production parameters: 64 MiB memory, 3 iterations, 1 lane.
// Lower these via the constructor only in tests — never in production code.
const int _kDefaultMemoryKib = 65536;
const int _kDefaultIterations = 3;
const int _kDefaultLanes = 1;
const int _kHashLength = 32; // output bytes
const int _kSaltLength = 16; // salt bytes

/// Argon2id password hasher that produces and parses PHC-format strings.
///
/// PHC format: `$argon2id$v=19$m=<mem>,t=<iter>,p=<lanes>$<salt_b64>$<hash_b64>`
///
/// Parameters in the stored string are authoritative for verification, so
/// raising the defaults automatically upgrades future hashes without
/// invalidating existing ones.
class Argon2idPasswordHasher implements PasswordHasher {
  const Argon2idPasswordHasher({
    int memoryKib = _kDefaultMemoryKib,
    int iterations = _kDefaultIterations,
    int lanes = _kDefaultLanes,
  }) : _memoryKib = memoryKib,
       _iterations = iterations,
       _lanes = lanes;

  final int _memoryKib;
  final int _iterations;
  final int _lanes;

  @override
  Future<String> hash(String password) async {
    final salt = _generateSalt();
    final hashBytes = _compute(password, salt, _memoryKib, _iterations, _lanes);
    return _encode(salt, hashBytes, _memoryKib, _iterations, _lanes);
  }

  @override
  Future<bool> verify(String password, String storedHash) async {
    try {
      final parsed = _parse(storedHash);
      final computed = _compute(
        password,
        parsed.salt,
        parsed.memory,
        parsed.iterations,
        parsed.lanes,
      );
      return _constantTimeEqual(computed, parsed.hash);
    } catch (_) {
      // Malformed or sentinel hash — indistinguishable from wrong password.
      return false;
    }
  }

  Uint8List _generateSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(_kSaltLength, (_) => rng.nextInt(256)),
    );
  }

  Uint8List _compute(
    String password,
    Uint8List salt,
    int memoryKib,
    int iterations,
    int lanes,
  ) {
    final params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      memory: memoryKib,
      iterations: iterations,
      lanes: lanes,
      version: Argon2Parameters.ARGON2_VERSION_13,
    );
    final gen = Argon2BytesGenerator()..init(params);
    final out = Uint8List(_kHashLength);
    gen.generateBytesFromString(password, out);
    return out;
  }

  String _encode(
    Uint8List salt,
    Uint8List hash,
    int memory,
    int iterations,
    int lanes,
  ) {
    // base64url without padding per PHC spec.
    final saltB64 = base64Url.encode(salt).replaceAll('=', '');
    final hashB64 = base64Url.encode(hash).replaceAll('=', '');
    return '\$argon2id\$v=19\$m=$memory,t=$iterations,p=$lanes\$$saltB64\$$hashB64';
  }

  _ParsedHash _parse(String encoded) {
    // Expected 6 parts when split by '$': ['', 'argon2id', 'v=19', 'm=…', salt, hash]
    final parts = encoded.split('\$');
    if (parts.length != 6 || parts[1] != 'argon2id') {
      throw const FormatException('Not a valid Argon2id PHC string');
    }
    final paramMap = <String, int>{};
    for (final kv in parts[3].split(',')) {
      final sep = kv.indexOf('=');
      paramMap[kv.substring(0, sep)] = int.parse(kv.substring(sep + 1));
    }
    return _ParsedHash(
      salt: base64Url.decode(_padBase64(parts[4])),
      hash: base64Url.decode(_padBase64(parts[5])),
      memory: paramMap['m']!,
      iterations: paramMap['t']!,
      lanes: paramMap['p']!,
    );
  }

  String _padBase64(String s) {
    final mod = s.length % 4;
    return mod == 0 ? s : '$s${'=' * (4 - mod)}';
  }

  bool _constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _ParsedHash {
  const _ParsedHash({
    required this.salt,
    required this.hash,
    required this.memory,
    required this.iterations,
    required this.lanes,
  });

  final Uint8List salt;
  final Uint8List hash;
  final int memory;
  final int iterations;
  final int lanes;
}
