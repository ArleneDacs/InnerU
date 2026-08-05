import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlPattern = RegExp(
  r'((https?:\/\/)[^\s]+)',
  caseSensitive: false,
);

/// Splits [text] into spans, wrapping any http(s) URL substring as a
/// tappable, distinctly-styled span. Covers YouTube/Facebook/Instagram/
/// TikTok/plain websites the same way -- they're all just http(s) URLs;
/// the OS itself resolves a tap to the installed app (via universal/app
/// links) or the default browser when the app isn't installed, so no
/// per-domain special-casing is needed here.
List<InlineSpan> buildLinkifiedSpans(
  String text, {
  required TextStyle baseStyle,
  required TextStyle linkStyle,
  required void Function(String url) onTap,
}) {
  final matches = _urlPattern.allMatches(text).toList();
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start), style: baseStyle));
    }
    final url = match.group(0)!;
    spans.add(
      TextSpan(
        text: url,
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = () => onTap(url),
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
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;

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
        ),
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
