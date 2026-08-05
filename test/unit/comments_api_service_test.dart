import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/comments_api_service.dart';

void main() {
  group('CommunityComment.fromJson', () {
    Map<String, dynamic> baseJson() => {
          'id': 'c1',
          'postId': 'p1',
          'userId': 'u1',
          'username': 'karina',
          'comment': 'hello',
          'createdAt': '2026-08-04T00:00:00Z',
          'updatedAt': null,
          'profilePic': null,
          'reactionsCount': 0,
          'reactedByMe': false,
          'parentId': null,
        };

    test('defaults mentions to an empty list when missing', () {
      final comment = CommunityComment.fromJson(baseJson());
      expect(comment.mentions, isEmpty);
    });

    test('parses mentions into userId/name pairs', () {
      final json = baseJson()
        ..['mentions'] = [
          {'userId': 'u2', 'name': 'Jordan Rivera'},
        ];
      final comment = CommunityComment.fromJson(json);
      expect(comment.mentions, [
        {'userId': 'u2', 'name': 'Jordan Rivera'},
      ]);
    });
  });
}
