import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/validation/text_normalizer.dart';

void main() {
  group('TextNormalizer', () {
    test('normalizeOptional trims and converts empty to null', () {
      expect(TextNormalizer.normalizeOptional('  hi  '), 'hi');
      expect(TextNormalizer.normalizeOptional('   '), isNull);
      expect(TextNormalizer.normalizeOptional(''), isNull);
      expect(TextNormalizer.normalizeOptional(null), isNull);
    });

    test('preserves Arabic Unicode content', () {
      expect(TextNormalizer.normalizeOptional('  القانون  '), 'القانون');
    });

    test('collapseWhitespace collapses runs and trims', () {
      expect(TextNormalizer.collapseWhitespace('  a   b\tc '), 'a b c');
    });

    test('detects disallowed control chars (no line breaks)', () {
      expect(
        TextNormalizer.hasDisallowedControlChars('ab', allowLineBreaks: false),
        isFalse,
      );
      expect(
        TextNormalizer.hasDisallowedControlChars(
          'a\nb',
          allowLineBreaks: false,
        ),
        isTrue,
      );
      expect(
        TextNormalizer.hasDisallowedControlChars(
          'a\tb',
          allowLineBreaks: false,
        ),
        isTrue,
      );
    });

    test('allows line breaks but not tabs when permitted', () {
      expect(
        TextNormalizer.hasDisallowedControlChars('a\nb', allowLineBreaks: true),
        isFalse,
      );
      expect(
        TextNormalizer.hasDisallowedControlChars(
          'a\r\nb',
          allowLineBreaks: true,
        ),
        isFalse,
      );
      expect(
        TextNormalizer.hasDisallowedControlChars('a\tb', allowLineBreaks: true),
        isTrue,
      );
    });

    test('isIsoDate accepts real ISO dates and rejects others', () {
      expect(TextNormalizer.isIsoDate('2026-06-07'), isTrue);
      expect(TextNormalizer.isIsoDate('2026-13-01'), isFalse);
      expect(TextNormalizer.isIsoDate('2026-02-30'), isFalse);
      expect(TextNormalizer.isIsoDate('2026-6-7'), isFalse);
      expect(TextNormalizer.isIsoDate('07/06/2026'), isFalse);
    });
  });
}
