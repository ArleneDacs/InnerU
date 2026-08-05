import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.username,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
    this.profilePic,
  });

  final String id;
  final String postId;
  final String userId;
  final String username;
  final String comment;
  final String? createdAt;
  final String? updatedAt;
  final String? profilePic;

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    return CommunityComment(
      id: json['id']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Unknown',
      comment: json['comment']?.toString() ?? '',
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      profilePic: json['profilePic'] as String?,
    );
  }
}

class CommentsApiService {
  CommentsApiService._();

  static final CommentsApiService instance = CommentsApiService._();

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<CommunityComment>> fetchComments(String postId) async {
    final response = await _api.getJson(
      '/api/community/posts/$postId/comments',
      token: _token,
    );
    final raw = response['comments'];
    if (raw is! List) return const <CommunityComment>[];
    return raw
        .whereType<Map>()
        .map((comment) => CommunityComment.fromJson(
              Map<String, dynamic>.from(comment),
            ))
        .toList();
  }

  Future<CommunityComment> addComment({
    required String postId,
    required String comment,
  }) async {
    final response = await _api.postJson(
      '/api/community/posts/$postId/comments',
      {'comment': comment},
      token: _token,
    );
    final raw = response['comment'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Comment response was invalid.');
    }
    return CommunityComment.fromJson(raw);
  }

  Future<CommunityComment> updateComment({
    required String postId,
    required String commentId,
    required String comment,
  }) async {
    final response = await _api.patchJson(
      '/api/community/posts/$postId/comments/$commentId',
      {'comment': comment},
      token: _token,
    );
    final raw = response['comment'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Comment response was invalid.');
    }
    return CommunityComment.fromJson(raw);
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    await _api.deleteJson(
      '/api/community/posts/$postId/comments/$commentId',
      token: _token,
    );
  }
}
