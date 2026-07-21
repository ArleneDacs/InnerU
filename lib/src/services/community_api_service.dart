import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

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
}
