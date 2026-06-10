// lib/core/validation/category_name.dart

/// Shared, pure category-name cleaning, comparison normalization, and character
/// validation.
///
/// This is the single source of truth for the "same name" rule. It is reused by
/// the category-management service/repository checks, the reference seeder, the
/// v1 -> v2 migration backfill, and the tests, so a display name and its
/// normalized comparison value can never drift apart.
///
/// Two distinct concerns live here:
///
/// * [cleanCategoryDisplayName] produces the *human-readable* value that is
///   stored and shown. It only trims and collapses whitespace; it never alters
///   spelling or strips meaningful characters.
/// * [normalizedCategoryNameAr] / [normalizedCategoryNameEn] produce the
///   *internal* comparison value used only for duplicate detection and the
///   SQLite unique indexes. These are never displayed.
///
/// A deliberate dependency note: no third-party Unicode package is added. The
/// equivalences this milestone requires (whitespace, case, Arabic
/// diacritics/tatweel/alef/ya, and decomposed combining marks) are fully and
/// deterministically expressible with the explicit code-point transforms below,
/// which keeps the offline Windows build free of an extra, less-maintained
/// dependency. The combining-mark stripping collapses canonically-decomposed
/// sequences to their base letters for our duplicate-detection purpose. Every
/// character set is expressed as numeric code points so the source contains no
/// fragile invisible literals.
library;

/// Collapses every internal whitespace run to a single normal space.
final RegExp _whitespaceRun = RegExp(r'\s+');

// Arabic code points referenced by the normalization rules.
const int _tatweel = 0x0640; // ـ kashida / elongation
const int _bareAlef = 0x0627; // ا canonical alef target
const int _alefMaqsura = 0x0649; // ى
const int _ya = 0x064A; // ي canonical maqsura target

/// Alef variants folded to the bare alef (U+0627): madda (U+0622), hamza above
/// (U+0623), hamza below (U+0625), and alef wasla (U+0671).
const Set<int> _alefVariants = {0x0622, 0x0623, 0x0625, 0x0671};

/// True for combining marks removed before comparison: general Latin combining
/// diacritics (U+0300–U+036F) and the Arabic mark ranges — tashkeel and Quranic
/// annotation marks (U+0610–U+061A, U+064B–U+065F) plus the superscript alef
/// (U+0670).
bool _isCombiningMark(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    (c >= 0x0610 && c <= 0x061A) ||
    (c >= 0x064B && c <= 0x065F) ||
    c == 0x0670;

/// True for control characters and invisible formatting characters that are
/// rejected in a display name: C0/C1 controls (so tab, newline, and carriage
/// return are rejected), zero-width and bidi formatting characters
/// (U+200B–U+200F, U+202A–U+202E, U+2066–U+2069), the word joiner / invisible
/// operators (U+2060–U+2064), and the BOM / zero-width no-break space (U+FEFF).
/// Any of these could otherwise disguise a duplicate.
bool _isForbidden(int c) =>
    c <= 0x001F ||
    (c >= 0x007F && c <= 0x009F) ||
    (c >= 0x200B && c <= 0x200F) ||
    (c >= 0x202A && c <= 0x202E) ||
    (c >= 0x2060 && c <= 0x2064) ||
    (c >= 0x2066 && c <= 0x2069) ||
    c == 0xFEFF;

/// True for an Arabic-script *letter*. This is deliberately narrower than "any
/// character in an Arabic block": the Arabic-Indic digits (U+0660–U+0669,
/// U+06F0–U+06F9), the Arabic punctuation (comma U+060C, etc.), the tatweel
/// (U+0640), and the tashkeel marks are NOT letters and so do not satisfy the
/// "contains an Arabic letter" rule. The covered ranges are the core Arabic
/// letters (U+0621–U+063A and U+0641–U+064A) and the Arabic letter extensions
/// (U+0671–U+06D3) that include the alef-wasla and the additional Perso-Arabic
/// letters.
bool _isArabicLetter(int c) =>
    (c >= 0x0621 && c <= 0x063A) ||
    (c >= 0x0641 && c <= 0x064A) ||
    (c >= 0x0671 && c <= 0x06D3);

/// True for a Latin-script letter: basic ASCII A–Z / a–z plus the accented
/// Latin-1 Supplement and Latin Extended-A/B letters (U+00C0–U+024F), excluding
/// the multiplication and division signs (U+00D7, U+00F7) which sit inside that
/// block but are math symbols rather than letters.
bool _isLatinLetter(int c) =>
    (c >= 0x0041 && c <= 0x005A) ||
    (c >= 0x0061 && c <= 0x007A) ||
    (c >= 0x00C0 && c <= 0x024F && c != 0x00D7 && c != 0x00F7);

/// Cleans a display name for storage: trims surrounding whitespace and collapses
/// every internal whitespace run to a single normal space. Spelling and all
/// visible characters are preserved. This is what gets persisted and shown.
String cleanCategoryDisplayName(String value) =>
    value.trim().replaceAll(_whitespaceRun, ' ');

/// Whether [value] contains any control or invisible-formatting character that
/// must be rejected. Checked on the *raw* input (before cleaning) so that
/// newline/tab cannot be silently folded into a space by whitespace collapsing.
bool categoryNameHasForbiddenCharacters(String value) =>
    value.runes.any(_isForbidden);

/// Whether [value] contains at least one Arabic-script letter. Digits,
/// punctuation, spaces, and diacritics do not count. Used by the Arabic-name
/// field to require genuine Arabic content and to reject Arabic letters in the
/// English field.
bool categoryNameHasArabicLetter(String value) =>
    value.runes.any(_isArabicLetter);

/// Whether [value] contains at least one Latin-script letter. Digits,
/// punctuation, and spaces do not count. Used by the English-name field to
/// require genuine Latin content and to reject Latin letters in the Arabic
/// field.
bool categoryNameHasLatinLetter(String value) =>
    value.runes.any(_isLatinLetter);

/// Cleaned, case-folded, combining-mark-stripped form shared by both languages.
String _foldCommon(String value) {
  final String cleaned = cleanCategoryDisplayName(value).toLowerCase();
  final StringBuffer out = StringBuffer();
  for (final int c in cleaned.runes) {
    if (!_isCombiningMark(c)) out.writeCharCode(c);
  }
  return out.toString();
}

/// Canonical comparison value for an English (or other Latin-script) category
/// name: cleaned, case-folded, and stripped of combining marks.
String normalizedCategoryNameEn(String value) => _foldCommon(value);

/// Canonical comparison value for an Arabic category name. Applies the base
/// normalization plus Arabic-specific folding: removes tatweel and diacritics,
/// unifies alef variants to bare alef, and maps alef-maqsura to ya. It
/// deliberately does NOT fold ة (U+0629) to ه (U+0647) — that can change
/// meaning.
String normalizedCategoryNameAr(String value) {
  final String cleaned = cleanCategoryDisplayName(value);
  final StringBuffer out = StringBuffer();
  for (final int c in cleaned.runes) {
    if (c == _tatweel) continue;
    if (_alefVariants.contains(c)) {
      out.writeCharCode(_bareAlef);
    } else if (c == _alefMaqsura) {
      out.writeCharCode(_ya);
    } else {
      out.writeCharCode(c);
    }
  }
  // Base normalization removes remaining combining diacritics and folds case.
  return _foldCommon(out.toString());
}
