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
    required this.profilePic,
    required this.reactionsCount,
    required this.reactedByMe,
    required this.parentId,
  });

  final String id;
  final String postId;
  final String userId;
  final String username;
  final String comment;
  final String? createdAt;
  final String? updatedAt;
  final String? profilePic;
  final int reactionsCount;
  final bool reactedByMe;
  final String? parentId;

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final rawReactionsCount = json['reactionsCount'];
    return CommunityComment(
      id: json['id']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Unknown',
      comment: json['comment']?.toString() ?? '',
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      profilePic: json['profilePic'] as String?,
      reactionsCount: rawReactionsCount is num
          ? rawReactionsCount.toInt()
          : int.tryParse(rawReactionsCount?.toString() ?? '') ?? 0,
      reactedByMe: json['reactedByMe'] == true,
      parentId: json['parentId'] as String?,
    );
  }
}

class CommentReactionState {
  const CommentReactionState({
    required this.commentId,
    required this.reactionsCount,
    required this.reactedByMe,
  });

  factory CommentReactionState.fromJson(Map<String, dynamic> json) {
    final rawReactionsCount = json['reactionsCount'];
    return CommentReactionState(
      commentId: json['commentId']?.toString() ?? '',
      reactionsCount: rawReactionsCount is num
          ? rawReactionsCount.toInt()
          : int.tryParse(rawReactionsCount?.toString() ?? '') ?? 0,
      reactedByMe: json['reactedByMe'] == true,
    );
  }

  final String commentId;
  final int reactionsCount;
  final bool reactedByMe;
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
    String? parentId,
  }) async {
    final response = await _api.postJson(
      '/api/community/posts/$postId/comments',
      {
        'comment': comment,
        if (parentId != null) 'parentId': parentId,
      },
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

  Future<CommentReactionState> reactComment({
    required String postId,
    required String commentId,
  }) async {
    final response = await _api.postJson(
      '/api/community/posts/$postId/comments/$commentId/reactions',
      const {},
      token: _token,
    );
    return CommentReactionState.fromJson(response);
  }

  Future<CommentReactionState> unreactComment({
    required String postId,
    required String commentId,
  }) async {
    final response = await _api.deleteJson(
      '/api/community/posts/$postId/comments/$commentId/reactions',
      token: _token,
    );
    return CommentReactionState.fromJson(response);
  }
}
