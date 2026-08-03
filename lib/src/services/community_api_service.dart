import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class PostHeartState {
  const PostHeartState({
    required this.heartsCount,
    required this.heartedByMe,
  });

  final int heartsCount;
  final bool heartedByMe;

  factory PostHeartState.fromJson(Map<String, dynamic> json) {
    final rawCount = json['heartsCount'];
    return PostHeartState(
      heartsCount: rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '') ?? 0,
      heartedByMe: json['heartedByMe'] == true,
    );
  }
}

class CommunityApiService {
  CommunityApiService._();

  static final CommunityApiService instance = CommunityApiService._();

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<Note>> fetchPosts({String? category}) async {
    final response = await _api.getJson(
      category == null || category.trim().isEmpty
          ? '/api/community/posts'
          : '/api/community/posts?category=${Uri.encodeComponent(category.trim())}',
      token: _token,
    );
    final rawPosts = response['posts'];
    if (rawPosts is! List) return const <Note>[];

    return rawPosts
        .whereType<Map>()
        .map((post) => Note.fromMap(Map<String, dynamic>.from(post)))
        .toList();
  }

  Future<Note> createPost({
    required String title,
    required String category,
    required List<Map<String, String>> note,
    required int color,
    bool saved = false,
  }) async {
    final response = await _api.postJson(
      '/api/community/posts',
      {
        'title': title,
        'category': category,
        'note': note,
        'color': color,
        'saved': saved,
      },
      token: _token,
    );

    final post = response['post'];
    if (post is! Map<String, dynamic>) {
      throw ApiException(500, 'Community post response was invalid.');
    }

    return Note.fromMap(post);
  }

  Future<void> setSaved({
    required String postId,
    required bool saved,
  }) async {
    await _api.patchJson(
      '/api/community/posts/$postId',
      {'saved': saved},
      token: _token,
    );
  }

  Future<void> deletePost(String postId) async {
    await _api.deleteJson(
      '/api/community/posts/$postId',
      token: _token,
    );
  }

  // Liking a post you already liked (e.g. a double tap) is a harmless
  // no-op server-side -- the backend's unique (post, user) constraint on
  // the hearts table means it always returns the current, authoritative
  // count instead of inflating it.
  Future<PostHeartState> heartPost(String postId) async {
    final response = await _api.postJson(
      '/api/community/posts/$postId/hearts',
      const {},
      token: _token,
    );
    return PostHeartState.fromJson(response);
  }

  Future<PostHeartState> unheartPost(String postId) async {
    final response = await _api.deleteJson(
      '/api/community/posts/$postId/hearts',
      token: _token,
    );
    return PostHeartState.fromJson(response);
  }
}
