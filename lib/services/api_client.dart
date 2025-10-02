import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/post.dart';

class ApiClient {
  static const _base = 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app';

  final http.Client _http;
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/115 Safari/537.36',
        'Content-Type': 'application/json',
      };

  Future<({List<Post> posts, bool hasMore})> getPosts({
    required int appUserId,
    required int page,
    required String token,
  }) async {
    final url = Uri.parse('$_base/get-posts?app_user_id=$appUserId&page=$page');
    final res = await _http.get(url, headers: _headers(token));
    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode} al obtener posts');
    }
    final body = json.decode(res.body) as Map<String, dynamic>;
    final list = (body['data'] as List? ?? [])
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList();
    final hasMore = list.isNotEmpty;
    return (posts: list, hasMore: hasMore);
  }

  Future<Set<int>> getLikedPostIds({
    required String appUserId,
    required String token,
    required int page,
  }) async {
    final url = Uri.parse('$_base/like-posts-app-user?app_user_id=$appUserId&page=$page');
    final res = await _http.get(url, headers: _headers(token));
    if (res.statusCode != 200) throw Exception('No se pudieron obtener likes');
    final data = json.decode(res.body);
    final items = (data['data'] as List? ?? []);
    return items.map<int>((e) => (e['id'] as int)).toSet();
  }

  Future<Set<int>> getAllLikedPostIdsPaged({
    required String appUserId,
    required String token,
  }) async {
    final liked = <int>{};
    var page = 1;
    while (true) {
      final batch = await getLikedPostIds(appUserId: appUserId, token: token, page: page);
      if (batch.isEmpty) break;
      liked.addAll(batch);
      page++;
    }
    return liked;
  }

  Future<Set<int>> getSavedPostIds({
    required String appUserId,
    required String token,
  }) async {
    final url = Uri.parse('$_base/saved-posts?app_user_id=$appUserId');
    final res = await _http.get(url, headers: _headers(token));
    if (res.statusCode != 200) throw Exception('No se pudieron obtener guardados');
    final data = json.decode(res.body);
    final items = (data['data'] as List? ?? []);
    return items.map<int>((e) => (e['id'] as int)).toSet();
  }

  Future<void> likePost({
    required String appUserId,
    required int postId,
    required String token,
  }) async {
    final url = Uri.parse('$_base/like-post');
    final res = await _http.post(url, headers: _headers(token), body: jsonEncode({
      'app_user_id': appUserId, 'post_id': '$postId'
    }));
    if (res.statusCode != 200) {
      throw Exception(json.decode(res.body)['message'] ?? 'Error al dar like');
    }
  }

  Future<void> removeLike({
    required String appUserId,
    required int postId,
    required String token,
  }) async {
    final url = Uri.parse('$_base/remove-like-post');
    final res = await _http.delete(url, headers: _headers(token), body: jsonEncode({
      'app_user_id': appUserId, 'post_id': '$postId'
    }));
    if (res.statusCode != 200) {
      throw Exception(json.decode(res.body)['message'] ?? 'Error al quitar like');
    }
  }

  Future<void> savePost({
    required String appUserId,
    required int postId,
    required String token,
  }) async {
    final url = Uri.parse('$_base/save-post');
    final res = await _http.post(url, headers: _headers(token), body: jsonEncode({
      'app_user_id': appUserId, 'post_id': '$postId'
    }));
    if (res.statusCode != 200) {
      throw Exception(json.decode(res.body)['message'] ?? 'Error al guardar');
    }
  }

  Future<void> removeSaved({
    required String appUserId,
    required int postId,
    required String token,
  }) async {
    final url = Uri.parse('$_base/remove-saved-post');
    final res = await _http.delete(url, headers: _headers(token), body: jsonEncode({
      'app_user_id': appUserId, 'post_id': '$postId'
    }));
    if (res.statusCode != 200) {
      throw Exception(json.decode(res.body)['message'] ?? 'Error al quitar guardado');
    }
  }

  void close() => _http.close();
}
