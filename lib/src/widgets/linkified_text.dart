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
    return [TextSpan(text: text, style: baseStyle)];
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
      spans.add(TextSpan(text: text.substring(cursor, match.start), style: baseStyle));
    }
    final matchText = text.substring(match.start, match.end);
    final isUrl = match.type == _SpanMatchType.url;
    final style = isUrl ? linkStyle : (mentionStyle ?? linkStyle);
    final recognizer = isUrl
        ? (TapGestureRecognizer()..onTap = () => onTap(match.payload))
        : (onMentionTap == null
            ? null
            : (TapGestureRecognizer()..onTap = () => onMentionTap(match.payload)));
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
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
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
