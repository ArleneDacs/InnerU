import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/community_notification_target.dart';

void main() {
  group('CommunityNotificationTarget', () {
    test('uses nested API data with camelCase identifiers', () {
      final target = CommunityNotificationTarget.fromNotification({
        'id': 'notification-id',
        'data': {'postId': '42', 'commentId': 7},
      });

      expect(target.postId, '42');
      expect(target.commentId, '7');
    });

    test('uses flattened OneSignal payload identifiers', () {
      final target = CommunityNotificationTarget.fromNotification({
        'notification_id': 'notification-id',
        'type': 'community_heart',
        'postId': 42,
      });

      expect(target.postId, '42');
      expect(target.commentId, isNull);
    });

    test('accepts JSON-encoded legacy data and snake_case aliases', () {
      final target = CommunityNotificationTarget.fromNotification({
        'data': '{"post_id":"42","comment_id":"7"}',
      });

      expect(target.postId, '42');
      expect(target.commentId, '7');
    });

    test('falls back to top-level identifiers when nested data is malformed',
        () {
      final target = CommunityNotificationTarget.fromNotification({
        'data': 'not JSON',
        'community_post_id': '42',
        'note_comment_id': '7',
      });

      expect(target.postId, '42');
      expect(target.commentId, '7');
    });
  });
}
