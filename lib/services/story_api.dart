import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/story.dart';

class StoryApi {
  static const String baseUrl = 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app';
  final _storage = const FlutterSecureStorage();

  Future<List<Story>> getStories() async {
    final token = await _storage.read(key: 'access_token');
    final userId = await _storage.read(key: 'user_id');
    if (token == null || userId == null) throw Exception('Token o user_id faltante.');

    final response = await http.get(
      Uri.parse('$baseUrl/get-stories?app_user_id=$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List list = data['data'];
      return list.map((e) => Story.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener historias: ${response.statusCode}');
    }
  }

  Future<void> likeStory(int storyId) async {
    final token = await _storage.read(key: 'access_token');
    final userId = await _storage.read(key: 'user_id');
    await http.post(
      Uri.parse('$baseUrl/like-story'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'app_user_id': userId, 'story_id': storyId.toString()},
    );
  }

  Future<void> removeLikeStory(int storyId) async {
    final token = await _storage.read(key: 'access_token');
    final userId = await _storage.read(key: 'user_id');
    await http.delete(
      Uri.parse('$baseUrl/remove-like-story'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'app_user_id': userId, 'story_id': storyId.toString()},
    );
  }
}
