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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan Rivera'));
    await tester.pumpAndSettle();

    expect(controller.text, 'hey @Jordan Rivera ');
    expect(key.currentState!.selectedMentions.length, 1);
    expect(key.currentState!.selectedMentions.first.id, '1');
  });
}
