import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/mention_api_service.dart';
import 'package:selfcare_projects/src/widgets/mention_text_field.dart';

void main() {
  testWidgets('typing @ followed by text shows matching suggestions',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionTextField(
            controller: controller,
            searchOverride: (query) async => [
              const MentionCandidate(id: '1', name: 'Jordan Rivera'),
              const MentionCandidate(id: '2', name: 'Jordan Lee'),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hey @Jor');
    // The suggestion search is debounced by 250ms via a plain `Timer`, which
    // isn't tied to Flutter's frame scheduler, so `pumpAndSettle()` (which
    // only keeps pumping while a frame is scheduled) settles too early and
    // never lets the Timer fire. Pump explicitly past the debounce window
    // instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Jordan Rivera'), findsOneWidget);
    expect(find.text('Jordan Lee'), findsOneWidget);
  });

  testWidgets('selecting a suggestion inserts the name and records the mention',
      (tester) async {
    final controller = TextEditingController();
    final key = GlobalKey<MentionTextFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionTextField(
            key: key,
            controller: controller,
            searchOverride: (query) async =>
                [const MentionCandidate(id: '1', name: 'Jordan Rivera')],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hey @Jor');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Jordan Rivera'));
    await tester.pumpAndSettle();

    expect(controller.text, 'hey @Jordan Rivera ');
    expect(key.currentState!.selectedMentions.length, 1);
    expect(key.currentState!.selectedMentions.first.id, '1');
  });

  testWidgets(
      'debounces incremental typing into a single search with the final query',
      (tester) async {
    final controller = TextEditingController();
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionTextField(
            controller: controller,
            searchOverride: (query) async {
              queries.add(query);
              return [const MentionCandidate(id: '1', name: 'Jordan Rivera')];
            },
          ),
        ),
      ),
    );

    // Simulate keystrokes arriving one at a time, each well within the
    // 250ms debounce window of the previous one, so each new keystroke
    // should cancel and restart the pending search rather than letting it
    // fire. A non-debounced (or incorrectly-debounced) implementation would
    // search on every keystroke instead of once, at the end.
    await tester.enterText(find.byType(TextField), 'hey @J');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'hey @Jo');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'hey @Jor');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(queries, ['Jor']);
  });
}
