import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/widgets/linkified_text.dart';

void main() {
  const baseStyle = TextStyle(color: Colors.black);
  const linkStyle = TextStyle(color: Colors.blue);

  test('plain text with no URL produces a single non-tappable span', () {
    final spans = buildLinkifiedSpans(
      'just some text',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
    );
    expect(spans.length, 1);
    expect((spans.first as TextSpan).text, 'just some text');
    expect((spans.first as TextSpan).recognizer, isNull);
  });

  test('detects a bare https URL and wraps only that substring as a link', () {
    final spans = buildLinkifiedSpans(
      'Check this out: https://www.youtube.com/watch?v=xxxxx it is great',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
    );
    final texts = spans.map((s) => (s as TextSpan).text).toList();
    expect(texts, [
      'Check this out: ',
      'https://www.youtube.com/watch?v=xxxxx',
      ' it is great',
    ]);
    expect((spans[1] as TextSpan).style?.color, Colors.blue);
    expect((spans[1] as TextSpan).recognizer, isNotNull);
    expect((spans[0] as TextSpan).recognizer, isNull);
  });

  test('detects multiple URLs in the same text', () {
    final spans = buildLinkifiedSpans(
      'a.com then http://b.com/x then https://c.org',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
    );
    final links = spans
        .whereType<TextSpan>()
        .where((s) => s.recognizer != null)
        .map((s) => s.text)
        .toList();
    expect(links, ['http://b.com/x', 'https://c.org']);
  });

  test('tapping the link span invokes onTap with the exact URL', () {
    String? tapped;
    final spans = buildLinkifiedSpans(
      'go to https://example.com/page now',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (url) => tapped = url,
    );
    final linkSpan = spans.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    (linkSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(tapped, 'https://example.com/page');
  });
}
