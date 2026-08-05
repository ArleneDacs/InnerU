import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/models/comments_widget.dart';
import 'package:selfcare_projects/src/services/comments_api_service.dart';

void main() {
  testWidgets(
    'a submitted comment appears immediately, before the network call resolves',
    (tester) async {
      final completer = Completer<CommunityComment>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentWidget(
              postId: 'post-1',
              fetchCommentsOverride: () async => const <CommunityComment>[],
              addCommentOverride: (postId, comment) => completer.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Great post!');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(find.text('Great post!'), findsOneWidget);

      completer.complete(const CommunityComment(
        id: 'real-id',
        postId: 'post-1',
        userId: 'u1',
        username: 'Arlene',
        comment: 'Great post!',
        createdAt: '2026-08-04T00:00:00Z',
        updatedAt: null,
        profilePic: null,
        reactionsCount: 0,
        reactedByMe: false,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Great post!'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed submission rolls back the optimistic comment and shows an error snackbar',
    (tester) async {
      final completer = Completer<CommunityComment>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentWidget(
              postId: 'post-1',
              fetchCommentsOverride: () async => const <CommunityComment>[],
              addCommentOverride: (postId, comment) => completer.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Great post!');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      // Optimistic entry appears immediately, before the failure lands.
      expect(find.text('Great post!'), findsOneWidget);

      completer.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      // Rolled back: the optimistic entry is gone and an error is surfaced.
      expect(find.text('Great post!'), findsNothing);
      expect(
        find.text('Could not post your comment. Please try again.'),
        findsOneWidget,
      );
    },
  );
}
