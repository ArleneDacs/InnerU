import 'dart:convert';

/// The post/comment destination embedded in a Community notification.
///
/// In-app notifications carry their metadata below `data`, whereas OneSignal
/// exposes its additional data as the top-level tap payload. Older sends also
/// used snake_case keys and some clients serialize `data` as JSON. Keeping
/// that compatibility at this boundary ensures every notification entrypoint
/// navigates to the same post.
class CommunityNotificationTarget {
  const CommunityNotificationTarget({this.postId, this.commentId});

  final String? postId;
  final String? commentId;

  static const List<String> _postIdKeys = <String>[
    'postId',
    'post_id',
    'communityPostId',
    'community_post_id',
  ];

  static const List<String> _commentIdKeys = <String>[
    'commentId',
    'comment_id',
    'noteCommentId',
    'note_comment_id',
  ];

  /// Parses either an API notification (`data` nested under the row) or a
  /// push-tap payload (Community keys at the top level). Nested data takes
  /// precedence when both are present.
  factory CommunityNotificationTarget.fromNotification(
    Map<String, dynamic> notification,
  ) {
    final nestedData = _mapFrom(notification['data']);
    final sources = <Map<String, dynamic>>[
      if (nestedData != null) nestedData,
      notification,
    ];

    return CommunityNotificationTarget(
      postId: _firstId(sources, _postIdKeys),
      commentId: _firstId(sources, _commentIdKeys),
    );
  }

  static Map<String, dynamic>? _mapFrom(Object? raw) {
    if (raw is Map) {
      final result = <String, dynamic>{};
      raw.forEach((key, value) {
        if (key is String) result[key] = value;
      });
      return result;
    }

    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? _mapFrom(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static String? _firstId(
    List<Map<String, dynamic>> sources,
    List<String> keys,
  ) {
    for (final source in sources) {
      for (final key in keys) {
        final value = source[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }
}
