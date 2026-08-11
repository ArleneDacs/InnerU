import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

void main() {
  testWidgets('uses native emoji fallbacks for Community titles and bodies', (
    tester,
  ) async {
    const title = 'Mom’s Birthday 🎂🎉';
    const body = 'Celebrating together 🥳❤️';
    final note = Note(
      id: 'post-emoji',
      userId: 'user-1',
      username: 'arlen',
      title: title,
      note: const [
        {'type': 'text', 'value': body},
      ],
      createdAt: DateTime(2026, 8, 11),
      category: 'Add Value',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoteCard(note: note, onPressed: () {})),
      ),
    );

    const expectedFallbacks = [
      'Apple Color Emoji',
      'Segoe UI Emoji',
      'Noto Color Emoji',
    ];
    final titleText = tester.widget<Text>(find.text(title));
    expect(titleText.style?.fontFamilyFallback, expectedFallbacks);

    final bodyText = tester.widget<Text>(find.text(body));
    final bodySpan = bodyText.textSpan;
    expect(bodySpan, isA<TextSpan>());
    final contentSpan = (bodySpan! as TextSpan).children!.single as TextSpan;
    expect(contentSpan.style?.fontFamilyFallback, expectedFallbacks);
  });
}
