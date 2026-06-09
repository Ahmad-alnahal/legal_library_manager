// test/features/import/windows_path_policy_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/data/services/windows_path_policy.dart';
import 'package:path/path.dart' as p;

import 'support/import_test_support.dart';

void main() {
  const WindowsPathPolicy policy = WindowsPathPolicy();

  group('component-aware containment', () {
    test('equal paths are same and same-or-inside but not strictly inside', () {
      expect(policy.isSamePath(r'C:\Data\Lib', r'C:\Data\Lib'), isTrue);
      expect(policy.isSameOrInside(r'C:\Data\Lib', r'C:\Data\Lib'), isTrue);
      expect(policy.isStrictlyInside(r'C:\Data\Lib', r'C:\Data\Lib'), isFalse);
    });

    test('child path is inside parent', () {
      expect(
        policy.isStrictlyInside(r'C:\Data\Lib\sub', r'C:\Data\Lib'),
        isTrue,
      );
      expect(
        policy.isSameOrInside(r'C:\Data\Lib\sub\x', r'C:\Data\Lib'),
        isTrue,
      );
    });

    test('parent is not inside child', () {
      expect(policy.isSameOrInside(r'C:\Data', r'C:\Data\Lib'), isFalse);
    });

    test('siblings sharing a string prefix are NOT nested', () {
      // The classic unsafe-prefix bug: "C:\Data2" must not count as inside
      // "C:\Data".
      expect(policy.isSameOrInside(r'C:\Data2', r'C:\Data'), isFalse);
      expect(policy.isStrictlyInside(r'C:\Data2', r'C:\Data'), isFalse);
      expect(policy.isSamePath(r'C:\Data2', r'C:\Data'), isFalse);
    });

    test('comparison is case-insensitive (Windows semantics)', () {
      expect(policy.isSamePath(r'C:\Data\Lib', r'c:\data\LIB'), isTrue);
      expect(
        policy.isStrictlyInside(r'c:\data\lib\Sub', r'C:\DATA\LIB'),
        isTrue,
      );
    });

    test('forward/back separators normalize equivalently', () {
      expect(policy.isSamePath(r'C:\Data\Lib', 'C:/Data/Lib'), isTrue);
    });
  });

  group('canonicalize', () {
    test('produces an absolute normalized path', () {
      final String c = policy.canonicalize(r'C:\Data\..\Data\Lib');
      expect(p.isAbsolute(c), isTrue);
      expect(c.toLowerCase().endsWith(r'data\lib'.toLowerCase()), isTrue);
    });

    test('resolves a real directory symlink to its target when supported', () {
      final Directory root = makeTempDir('paths');
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory target = Directory(p.join(root.path, 'target'))
        ..createSync();
      final String linkPath = p.join(root.path, 'link');
      try {
        Link(linkPath).createSync(target.path);
      } on FileSystemException {
        // Creating links can require privileges on Windows; skip if unavailable.
        return;
      }
      final String canonical = policy.canonicalize(linkPath);
      expect(policy.isSamePath(canonical, target.path), isTrue);
    });
  });
}
