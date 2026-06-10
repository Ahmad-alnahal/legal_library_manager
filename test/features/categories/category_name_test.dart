import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/categories/domain/services/category_name.dart';

void main() {
  // Build single-character strings from code points so the source stays ASCII
  // and contains no fragile invisible literals.
  String ch(int c) => String.fromCharCode(c);

  // Inserts a diacritic after every non-space base letter, cycling through the
  // Arabic tashkeel + superscript alef. Used to prove diacritic removal without
  // hand-typing invisible marks.
  String diacritize(String base) {
    const List<int> marks = [
      0x064B, 0x064C, 0x064D, 0x064E, 0x064F, // tanwin, fatha, damma
      0x0650, 0x0651, 0x0652, 0x0670, // kasra, shadda, sukun, superscript alef
    ];
    final StringBuffer out = StringBuffer();
    int i = 0;
    for (final int r in base.runes) {
      out.writeCharCode(r);
      if (r != 0x20) {
        out.writeCharCode(marks[i % marks.length]);
        i++;
      }
    }
    return out.toString();
  }

  group('cleanCategoryDisplayName', () {
    test('trims surrounding and collapses internal whitespace', () {
      expect(cleanCategoryDisplayName('  القانون   العام '), 'القانون العام');
      expect(cleanCategoryDisplayName('Public   Law'), 'Public Law');
      expect(cleanCategoryDisplayName('  Public   Law  '), 'Public Law');
    });

    test('preserves visible spelling and useful punctuation', () {
      expect(
        cleanCategoryDisplayName('Law 2024 - (Section A)'),
        'Law 2024 - (Section A)',
      );
    });
  });

  group('normalizedCategoryNameEn', () {
    test('is case- and whitespace-insensitive', () {
      const String canonical = 'public law';
      expect(normalizedCategoryNameEn('Public Law'), canonical);
      expect(normalizedCategoryNameEn('public law'), canonical);
      expect(normalizedCategoryNameEn(' Public   Law '), canonical);
      expect(normalizedCategoryNameEn('PUBLIC LAW'), canonical);
    });
  });

  group('normalizedCategoryNameAr', () {
    final String canonical = normalizedCategoryNameAr('القانون العام');

    test('collapses whitespace variants', () {
      expect(normalizedCategoryNameAr('  القانون   العام '), canonical);
    });

    test('removes diacritics', () {
      expect(normalizedCategoryNameAr(diacritize('القانون العام')), canonical);
    });

    test('removes tatweel / kashida', () {
      final String tatweeled = 'القانون${ch(0x0640)}${ch(0x0640)} العام';
      expect(normalizedCategoryNameAr(tatweeled), canonical);
    });

    test('normalizes every alef variant to bare alef', () {
      final String bare = '${ch(0x0627)}حكام'; // احكام
      for (final int variant in [0x0622, 0x0623, 0x0625, 0x0671]) {
        expect(
          normalizedCategoryNameAr('${ch(variant)}حكام'),
          normalizedCategoryNameAr(bare),
          reason: 'alef variant U+${variant.toRadixString(16)}',
        );
      }
    });

    test('normalizes alef-maqsura to ya', () {
      final String maqsura = 'مبن${ch(0x0649)}'; // مبنى
      final String ya = 'مبن${ch(0x064A)}'; // مبني
      expect(normalizedCategoryNameAr(maqsura), normalizedCategoryNameAr(ya));
    });

    test('keeps taa-marbuta distinct from haa', () {
      final String taaMarbuta = 'مكتب${ch(0x0629)}'; // مكتبة
      final String haa = 'مكتب${ch(0x0647)}'; // مكتبه
      expect(
        normalizedCategoryNameAr(taaMarbuta),
        isNot(normalizedCategoryNameAr(haa)),
      );
    });
  });

  group('categoryNameHasForbiddenCharacters', () {
    test('allows letters, numbers, spaces, hyphens, and parentheses', () {
      expect(
        categoryNameHasForbiddenCharacters('Law 2024 - (Section A)'),
        isFalse,
      );
      expect(
        categoryNameHasForbiddenCharacters('القانون - رقم 12 (أ)'),
        isFalse,
      );
    });

    test('rejects control, newline, and tab characters', () {
      expect(categoryNameHasForbiddenCharacters('a${ch(0x09)}b'), isTrue);
      expect(categoryNameHasForbiddenCharacters('a\nb'), isTrue);
      expect(categoryNameHasForbiddenCharacters('a\rb'), isTrue);
      expect(categoryNameHasForbiddenCharacters('a${ch(0x00)}b'), isTrue);
    });

    test('rejects invisible formatting characters', () {
      for (final int c in [0x200B, 0x200C, 0x200E, 0x202A, 0x2066, 0xFEFF]) {
        expect(
          categoryNameHasForbiddenCharacters('a${ch(c)}b'),
          isTrue,
          reason: 'U+${c.toRadixString(16)} should be rejected',
        );
      }
    });
  });

  group('categoryNameHasArabicLetter', () {
    test('is true when an Arabic letter is present', () {
      expect(categoryNameHasArabicLetter('القانون العام'), isTrue);
      expect(categoryNameHasArabicLetter('القانون رقم 12'), isTrue);
      expect(categoryNameHasArabicLetter('القانون Public'), isTrue);
    });

    test('is false for Latin, digits, and punctuation only', () {
      expect(categoryNameHasArabicLetter('Public Law'), isFalse);
      expect(categoryNameHasArabicLetter('12345'), isFalse);
      expect(categoryNameHasArabicLetter('- ( ) / , & \''), isFalse);
    });

    test('does not count Arabic-Indic digits or the Arabic comma', () {
      // Arabic-Indic digits ٠١٢ and the Arabic comma ، are not letters.
      final String digitsAndComma =
          '${ch(0x0660)}${ch(0x0661)}${ch(0x0662)}${ch(0x060C)}';
      expect(categoryNameHasArabicLetter(digitsAndComma), isFalse);
    });

    test('does not count the tatweel', () {
      expect(categoryNameHasArabicLetter(ch(0x0640)), isFalse);
    });
  });

  group('categoryNameHasLatinLetter', () {
    test('is true when a Latin letter is present', () {
      expect(categoryNameHasLatinLetter('Public Law'), isTrue);
      expect(categoryNameHasLatinLetter('Law No. 12'), isTrue);
      expect(categoryNameHasLatinLetter('Public القانون'), isTrue);
    });

    test('is false for Arabic, digits, and punctuation only', () {
      expect(categoryNameHasLatinLetter('القانون العام'), isFalse);
      expect(categoryNameHasLatinLetter('12345'), isFalse);
      expect(categoryNameHasLatinLetter('- ( ) / , & \''), isFalse);
    });
  });
}
