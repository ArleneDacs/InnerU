import 'package:characters/characters.dart';

/// Returns at most [maxCharacters] user-perceived characters from [text].
///
/// Dart's [String.substring] is indexed by UTF-16 code units, so cutting a
/// post body at an arbitrary offset can split an emoji (or another composed
/// character) in half. The resulting invalid half is rendered as a missing
/// glyph on some platforms. Grapheme clusters keep a displayed character
/// intact, including emoji sequences joined with zero-width joiners.
String truncateToGraphemeClusters(String text, int maxCharacters) {
  if (text.isEmpty || maxCharacters <= 0) return '';

  final characters = text.characters;
  if (characters.length <= maxCharacters) return text;

  return characters.getRange(0, maxCharacters).toString();
}
