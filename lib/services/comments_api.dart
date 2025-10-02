// lib/services/comments_api.dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/paged.dart';
import '../models/comment.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}

class CommentsApi {
  static const _base = 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app';
  final _storage = const FlutterSecureStorage();
  final http.Client _client;
  CommentsApi({http.Client? client}) : _client = client ?? http.Client();

  /// Lee el bearer en este orden (compat con Postman y con tu app):
  /// BEARER_USER -> jwt_token -> access_token
  Future<String?> _readBearer() async {
    final a = await _storage.read(key: 'BEARER_USER');
    if (a != null && a.isNotEmpty) return a;
    final b = await _storage.read(key: 'jwt_token');
    if (b != null && b.isNotEmpty) return b;
    final c = await _storage.read(key: 'access_token');
    if (c != null && c.isNotEmpty) return c;
    return null;
  }

  Future<Map<String, String>> _headers() async {
    final token = await _readBearer();
    final h = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  // ------------ GETS ------------
  Future<Paged<Comment>> getComments({
    int? postId,
    int? pageId,
    int page = 1,
    int perPage = 10,
  }) async {
    final h = await _headers();
    final uri = Uri.parse('$_base/get-comments').replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
      if (postId != null) 'post_id': '$postId',
      if (pageId != null) 'page_id': '$pageId',
    });

    final r = await _client.get(uri, headers: h);
    _throwIfNotOk(r);

    final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final list = (m['data'] as List? ?? []).cast<Map<String, dynamic>>();
    return Paged<Comment>(
      currentPage: (m['current_page'] ?? 1) as int,
      data: list.map(Comment.fromJson).toList(),
      total: m['total'] as int?,
      lastPage: m['last_page'] as int?,
      perPage: m['per_page'] as int?,
    );
  }

  Future<Paged<Comment>> getChildComments({
    required int commentId,
    int page = 1,
    int perPage = 10,
  }) async {
    final h = await _headers();
    final uri = Uri.parse('$_base/get-child-comments').replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
      'comment_id': '$commentId',
    });
    final r = await _client.get(uri, headers: h);
    _throwIfNotOk(r);

    final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final list = (m['data'] as List? ?? []).cast<Map<String, dynamic>>();
    return Paged<Comment>(
      currentPage: (m['current_page'] ?? 1) as int,
      data: list.map(Comment.fromJson).toList(),
      total: m['total'] as int?,
      perPage: m['per_page'] as int?,
    );
  }

  Future<Map<String, dynamic>> getCommentLikes({
    required int commentId,
    int page = 1,
    int perPage = 10,
  }) async {
    final h = await _headers();
    final uri = Uri.parse('$_base/get-comment-likes').replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
      'comment_id': '$commentId',
    });
    final r = await _client.get(uri, headers: h);
    _throwIfNotOk(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ------------ WRITES (x-www-form-urlencoded como en Postman) ------------
  Future<Map<String, dynamic>> createComment({
    required int appUserId,
    required String content,
    int? postId,
    int? pageId,
    int? commentId, // reply
  }) async {
    final h = await _headers();
    final r = await _client.post(
      Uri.parse('$_base/save-comment'),
      headers: {...h, 'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'app_user_id': '$appUserId',
        'content': content,
        if (postId != null) 'post_id': '$postId',
        if (pageId != null) 'page_id': '$pageId',
        if (commentId != null) 'comment_id': '$commentId',
      },
    );
    _throwIfNotOk(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateComment({
    required int appUserId,
    required int commentId,
    required String content,
  }) async {
    final h = await _headers();
    final r = await _client.put(
      Uri.parse('$_base/update-comment'),
      headers: {...h, 'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'app_user_id': '$appUserId',
        'comment_id': '$commentId',
        'content': content,
      },
    );
    _throwIfNotOk(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteComment({
    required int appUserId,
    required int commentId,
  }) async {
    final h = await _headers();
    final req = http.Request('DELETE', Uri.parse('$_base/delete-comment'))
      ..headers.addAll({...h, 'Content-Type': 'application/x-www-form-urlencoded'})
      ..bodyFields = {'app_user_id': '$appUserId', 'comment_id': '$commentId'};
    final streamed = await _client.send(req);
    final r = await http.Response.fromStream(streamed);
    _throwIfNotOk(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> toggleLike({
    required int appUserId,
    required int commentId,
  }) async {
    final h = await _headers();
    final like = await _client.post(
      Uri.parse('$_base/like-comment'),
      headers: {...h, 'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'app_user_id': '$appUserId', 'comment_id': '$commentId'},
    );
    if (like.statusCode == 200) return;

    if (like.statusCode == 401) _throwIfNotOk(like);

    if (like.statusCode == 400 &&
        (like.body.contains('ya ha dado Like') ||
         like.body.toLowerCase().contains('ya'))) {
      final req = http.Request('DELETE', Uri.parse('$_base/remove-like-comment'))
        ..headers.addAll({...h, 'Content-Type': 'application/x-www-form-urlencoded'})
        ..bodyFields = {'app_user_id': '$appUserId', 'comment_id': '$commentId'};
      final streamed = await _client.send(req);
      final del = await http.Response.fromStream(streamed);
      _throwIfNotOk(del);
      return;
    }

    throw Exception('Error like: ${like.statusCode} ${like.body}');
  }

  void _throwIfNotOk(http.Response r) {
    if (r.statusCode == 401) {
      // intenta sacar un mensaje del backend (glosaRetorno)
      try {
        final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final msg = (m['glosaRetorno'] ?? m['message'] ?? 'No autorizado').toString();
        throw AuthException(msg);
      } catch (_) {
        throw AuthException('No autorizado (401). Token inválido o expirado.');
      }
    }
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
    }
  }

  void close() => _client.close();
}
