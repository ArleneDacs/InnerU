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

  const mentionStyle = TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold);

  test('detects an @Name mention and wraps only that substring as a tappable span', () {
    final spans = buildLinkifiedSpans(
      'hey @Jordan Rivera, welcome!',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
      mentions: const [MentionSpanTarget(userId: 'u1', name: 'Jordan Rivera')],
      mentionStyle: mentionStyle,
      onMentionTap: (_) {},
    );
    final texts = spans.map((s) => (s as TextSpan).text).toList();
    expect(texts, ['hey ', '@Jordan Rivera', ', welcome!']);
    expect((spans[1] as TextSpan).style?.color, Colors.deepPurple);
    expect((spans[1] as TextSpan).recognizer, isNotNull);
  });

  test('tapping the mention span invokes onMentionTap with the mentioned userId', () {
    String? tappedUserId;
    final spans = buildLinkifiedSpans(
      'hey @Jordan Rivera!',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
      mentions: const [MentionSpanTarget(userId: 'u1', name: 'Jordan Rivera')],
      onMentionTap: (userId) => tappedUserId = userId,
    );
    final mentionSpan =
        spans.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    (mentionSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(tappedUserId, 'u1');
  });

  test('a mention with no mentionStyle falls back to linkStyle', () {
    final spans = buildLinkifiedSpans(
      'hey @Jordan Rivera!',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
      mentions: const [MentionSpanTarget(userId: 'u1', name: 'Jordan Rivera')],
      onMentionTap: (_) {},
    );
    final mentionSpan =
        spans.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    expect(mentionSpan.style?.color, Colors.blue);
  });

  test('a mention renders styled but non-tappable when onMentionTap is omitted', () {
    final spans = buildLinkifiedSpans(
      'hey @Jordan Rivera!',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
      mentions: const [MentionSpanTarget(userId: 'u1', name: 'Jordan Rivera')],
      mentionStyle: mentionStyle,
    );
    final mentionSpan =
        spans.whereType<TextSpan>().firstWhere((s) => s.text == '@Jordan Rivera');
    expect(mentionSpan.style?.color, Colors.deepPurple);
    expect(mentionSpan.recognizer, isNull);
  });

  test('every occurrence of a mentioned name is highlighted', () {
    final spans = buildLinkifiedSpans(
      '@Jordan Rivera said hi, then @Jordan Rivera said bye',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
      mentions: const [MentionSpanTarget(userId: 'u1', name: 'Jordan Rivera')],
      onMentionTap: (_) {},
    );
    final mentionCount = spans
        .whereType<TextSpan>()
        .where((s) => s.text == '@Jordan Rivera')
        .length;
    expect(mentionCount, 2);
  });

  test('URLs and mentions in the same text are both linkified, in order', () {
    final spans = buildLinkifiedSpans(
      'hey @Jordan Rivera check https://example.com out',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
      mentions: const [MentionSpanTarget(userId: 'u1', name: 'Jordan Rivera')],
      mentionStyle: mentionStyle,
      onMentionTap: (_) {},
    );
    final texts = spans.map((s) => (s as TextSpan).text).toList();
    expect(texts, [
      'hey ',
      '@Jordan Rivera',
      ' check ',
      'https://example.com',
      ' out',
    ]);
  });

  test('a mention for an unmatched name does not alter the text', () {
    final spans = buildLinkifiedSpans(
      'just some text',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
      mentions: const [MentionSpanTarget(userId: 'u1', name: 'Nobody Here')],
      onMentionTap: (_) {},
    );
    expect(spans.length, 1);
    expect((spans.first as TextSpan).text, 'just some text');
  });
}
