import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

void main() {
  testWidgets('shows a readable fallback when a community image fails',
      (tester) async {
    final note = Note(
      id: 'post-1',
      userId: 'user-1',
      username: 'arlen',
      title: 'Meditation Moment',
      note: const [
        {'type': 'text', 'value': 'Sharing a calm moment.'},
        {'type': 'image', 'value': 'http://127.0.0.1:9/broken-image.jpg'},
      ],
      createdAt: DateTime(2026, 7, 23, 12, 20),
      category: 'Community',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCard(
            note: note,
            onPressed: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Image unavailable'), findsOneWidget);
  });
}
