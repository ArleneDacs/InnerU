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

/// A compact identity used only when someone asks to see who hearted a post.
/// It is intentionally fetched on demand rather than being attached to every
/// card in the community feed.
class CommunityPostLiker {
  const CommunityPostLiker({required this.id, required this.name});

  final String id;
  final String name;

  factory CommunityPostLiker.fromJson(Map<String, dynamic> json) {
    final rawName = json['name']?.toString().trim() ?? '';
    return CommunityPostLiker(
      id: json['id']?.toString() ?? '',
      name: rawName.isEmpty ? 'Member' : rawName,
    );
  }
}

/// One bounded page of post-heart identities.  [hasMore] lets the detail
/// sheet load another small page for popular posts without turning hover into
/// a large request.
class CommunityPostLikersPage {
  const CommunityPostLikersPage({
    required this.likers,
    required this.heartsCount,
    required this.page,
    required this.perPage,
    required this.hasMore,
  });

  final List<CommunityPostLiker> likers;
  final int heartsCount;
  final int page;
  final int perPage;
  final bool hasMore;

  factory CommunityPostLikersPage.fromJson(Map<String, dynamic> json) {
    final rawLikers = json['likers'];
    final likers = rawLikers is List
        ? rawLikers
            .whereType<Map>()
            .map(
              (liker) => CommunityPostLiker.fromJson(
                Map<String, dynamic>.from(liker),
              ),
            )
            .toList(growable: false)
        : const <CommunityPostLiker>[];

    int asInt(Object? value, int fallback) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return CommunityPostLikersPage(
      likers: likers,
      heartsCount: asInt(json['heartsCount'], 0),
      page: asInt(json['page'], 1),
      perPage: asInt(json['perPage'], 12),
      hasMore: json['hasMore'] == true,
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

  /// Fetches just one authorized post for a notification deep link.  This
  /// avoids reloading every community category merely to find its target.
  Future<Note> fetchPost(String postId) async {
    final response = await _api.getJson(
      '/api/community/posts/$postId',
      token: _token,
    );
    final post = response['post'];
    if (post is! Map) {
      throw ApiException(500, 'Community post response was invalid.');
    }
    return Note.fromMap(Map<String, dynamic>.from(post));
  }

  Future<Note> createPost({
    required String title,
    required String category,
    required List<Map<String, String>> note,
    required int color,
    bool saved = false,
    String? clientSubmissionId,
    List<Map<String, String>> mentions = const [],
  }) async {
    final response = await _api.postJson(
      '/api/community/posts',
      {
        'title': title,
        'category': category,
        'note': note,
        'color': color,
        'saved': saved,
        if (clientSubmissionId != null && clientSubmissionId.trim().isNotEmpty)
          'clientSubmissionId': clientSubmissionId.trim(),
        if (mentions.isNotEmpty) 'mentions': mentions,
      },
      token: _token,
    );

    final post = response['post'];
    if (post is! Map<String, dynamic>) {
      throw ApiException(500, 'Community post response was invalid.');
    }

    return Note.fromMap(post);
  }

  Future<Note> updatePost({
    required String postId,
    required String title,
    required String category,
    required List<Map<String, String>> note,
  }) async {
    final response = await _api.patchJson(
      '/api/community/posts/$postId',
      {
        'title': title,
        'category': category,
        'note': note,
      },
      token: _token,
    );

    final post = response['post'];
    if (post is! Map) {
      throw ApiException(500, 'Community post update response was invalid.');
    }

    return Note.fromMap(Map<String, dynamic>.from(post));
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

  Future<CommunityPostLikersPage> fetchPostLikers(
    String postId, {
    int page = 1,
    int perPage = 12,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(1, 25).toInt();
    final response = await _api.getJson(
      '/api/community/posts/$postId/hearts'
      '?page=$safePage&perPage=$safePerPage',
      token: _token,
    );
    return CommunityPostLikersPage.fromJson(response);
  }
}
