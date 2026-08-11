import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlPattern = RegExp(
  r'((https?:\/\/)[^\s]+)',
  caseSensitive: false,
);

/// A mentioned user to highlight within [buildLinkifiedSpans]-rendered
/// text. Matching is a literal substring search for `'@$name'`, so [name]
/// must match exactly what was inserted into the text at mention-selection
/// time (see `MentionTextField._select`). Tapping the rendered occurrence
/// invokes `onMentionTap` with [userId].
class MentionSpanTarget {
  const MentionSpanTarget({required this.userId, required this.name});
  final String userId;
  final String name;
}

enum _SpanMatchType { url, mention }

class _SpanMatch {
  const _SpanMatch({
    required this.start,
    required this.end,
    required this.type,
    required this.payload,
  });

  final int start;
  final int end;
  final _SpanMatchType type;
  // The URL text itself for a url match, or the mentioned user's id for a
  // mention match.
  final String payload;
}

/// Returns a native color-emoji family only for emoji grapheme clusters.
///
/// This must not be attached as a fallback to an entire body [TextStyle]: on
/// iOS, doing that can make CoreText choose Apple Color Emoji for ordinary
/// letters too, which renders the regular text as missing-glyph boxes.  By
/// giving *only* emoji clusters an explicit font family, normal text keeps the
/// app's existing font while emoji uses the system's native color face.
String _nativeEmojiFontFamily() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return 'Apple Color Emoji';
    case TargetPlatform.windows:
      return 'Segoe UI Emoji';
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
      return 'Noto Color Emoji';
  }
}

bool _isEmojiGrapheme(String grapheme) {
  for (final rune in grapheme.runes) {
    if ((rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        rune == 0x00A9 ||
        rune == 0x00AE ||
        rune == 0x203C ||
        rune == 0x2049 ||
        rune == 0x2122 ||
        rune == 0x2139 ||
        rune == 0x3030 ||
        rune == 0x303D ||
        rune == 0x3297 ||
        rune == 0x3299 ||
        rune == 0x20E3 ||
        rune == 0xFE0F) {
      return true;
    }
  }
  return false;
}

/// Splits [text] only when it contains emoji, keeping every non-emoji span on
/// [style] and putting just emoji grapheme clusters on the platform's native
/// emoji font. The [characters] iterator keeps joined/skin-tone emoji intact.
List<InlineSpan> buildEmojiAwareTextSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  final normalText = StringBuffer();

  void flushNormalText() {
    if (normalText.isEmpty) return;
    spans.add(TextSpan(text: normalText.toString(), style: style));
    normalText.clear();
  }

  for (final grapheme in text.characters) {
    if (!_isEmojiGrapheme(grapheme)) {
      normalText.write(grapheme);
      continue;
    }

    flushNormalText();
    spans.add(
      TextSpan(
        text: grapheme,
        style: style.copyWith(fontFamily: _nativeEmojiFontFamily()),
      ),
    );
  }

  flushNormalText();
  return spans;
}

/// Splits [text] into spans, wrapping any http(s) URL substring as a
/// tappable, distinctly-styled span. Covers YouTube/Facebook/Instagram/
/// TikTok/plain websites the same way -- they're all just http(s) URLs;
/// the OS itself resolves a tap to the installed app (via universal/app
/// links) or the default browser when the app isn't installed, so no
/// per-domain special-casing is needed here.
///
/// When [mentions] is non-empty, also highlights every literal `@Name`
/// occurrence (one entry per mention in the list, all its occurrences in
/// [text]) as a tappable span styled with [mentionStyle] (falling back to
/// [linkStyle] when not given), invoking [onMentionTap] with that mention's
/// userId on tap. URL and mention matches are merge-sorted by start offset
/// into a single pass so the two match kinds never have to be walked (and
/// kept mutually consistent) separately; URLs win if a mention match were
/// ever to overlap one (in practice `@Name` and `https://...` can't
/// overlap, since neither character set nests inside the other).
List<InlineSpan> buildLinkifiedSpans(
  String text, {
  required TextStyle baseStyle,
  required TextStyle linkStyle,
  required void Function(String url) onTap,
  List<MentionSpanTarget> mentions = const [],
  TextStyle? mentionStyle,
  void Function(String userId)? onMentionTap,
}) {
  final urlMatches = _urlPattern
      .allMatches(text)
      .map((m) => _SpanMatch(
            start: m.start,
            end: m.end,
            type: _SpanMatchType.url,
            payload: m.group(0)!,
          ))
      .toList();

  final mentionMatches = <_SpanMatch>[];
  for (final mention in mentions) {
    final needle = '@${mention.name}';
    if (needle == '@') continue;
    var searchFrom = 0;
    while (true) {
      final index = text.indexOf(needle, searchFrom);
      if (index == -1) break;
      mentionMatches.add(_SpanMatch(
        start: index,
        end: index + needle.length,
        type: _SpanMatchType.mention,
        payload: mention.userId,
      ));
      searchFrom = index + needle.length;
    }
  }

  // URLs win on overlap: drop any mention match that overlaps a URL
  // match's range before merging.
  final nonOverlappingMentions = mentionMatches.where((mention) {
    return !urlMatches.any(
      (url) => mention.start < url.end && mention.end > url.start,
    );
  });

  final matches = [...urlMatches, ...nonOverlappingMentions]
    ..sort((a, b) => a.start.compareTo(b.start));

  if (matches.isEmpty) {
    return buildEmojiAwareTextSpans(text, baseStyle);
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start < cursor) {
      // Two mention matches overlapping each other (e.g. one selected
      // name is a prefix of another at the same position) -- the text up
      // to `cursor` was already emitted by the previous match, so skip.
      continue;
    }
    if (match.start > cursor) {
      spans.addAll(
        buildEmojiAwareTextSpans(
          text.substring(cursor, match.start),
          baseStyle,
        ),
      );
    }
    final matchText = text.substring(match.start, match.end);
    final isUrl = match.type == _SpanMatchType.url;
    final style = isUrl ? linkStyle : (mentionStyle ?? linkStyle);
    final recognizer = isUrl
        ? (TapGestureRecognizer()..onTap = () => onTap(match.payload))
        : (onMentionTap == null
            ? null
            : (TapGestureRecognizer()
              ..onTap = () => onMentionTap(match.payload)));
    spans.add(
      TextSpan(
        text: matchText,
        style: style,
        recognizer: recognizer,
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.addAll(
      buildEmojiAwareTextSpans(text.substring(cursor), baseStyle),
    );
  }
  return spans;
}

/// A plain text widget that uses [buildEmojiAwareTextSpans].
///
/// Use this for non-linkified text such as Community post titles; linkified
/// content already receives the same handling through [LinkifiedText].
class EmojiAwareText extends StatelessWidget {
  const EmojiAwareText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(children: buildEmojiAwareTextSpans(text, baseStyle)),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

class LinkifiedText extends StatelessWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
    this.mentions = const [],
    this.mentionStyle,
    this.onMentionTap,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final List<MentionSpanTarget> mentions;
  final TextStyle? mentionStyle;
  final void Function(String userId)? onMentionTap;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final resolvedLinkStyle = (linkStyle ?? baseStyle).copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        children: buildLinkifiedSpans(
          text,
          baseStyle: baseStyle,
          linkStyle: resolvedLinkStyle,
          onTap: _open,
          mentions: mentions,
          mentionStyle: mentionStyle,
          onMentionTap: onMentionTap,
        ),
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
