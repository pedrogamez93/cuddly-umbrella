import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/notification_item.dart';


class NotificationsApi {
  NotificationsApi({
    required this.endpoint,
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String endpoint;
  final String apiKey;
  final http.Client _client;

 // 👇 OJO: r''' ... '''  (raw string ⇒ no hay interpolación de Dart)
static const _queryAll = r'''
  query GetNotifications($userEmail:String!){
    getNotifications(userEmail:$userEmail){
      id title message viewed viewedAt deleted deletedAt timestamp
    }
  }
''';

static const _queryUnread = r'''
  query GetUnreadNotifications($userEmail:String!){
    getUnreadNotifications(userEmail:$userEmail){
      id title message viewed viewedAt deleted deletedAt timestamp
    }
  }
''';


  Future<List<NotificationItem>> fetch({
    required String userEmail,
    bool onlyUnread = false,
  }) async {
    final body = jsonEncode({
      if (!onlyUnread) 'operationName': 'GetNotifications',
      'query': onlyUnread ? _queryUnread : _queryAll,
      'variables': {'userEmail': userEmail},
    });

    final resp = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey, // debe incluir prefijo da2-
          },
          body: body,
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('AppSync ${resp.statusCode}: ${resp.body}');
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;

    if (map['errors'] != null) {
      throw Exception('GraphQL errors: ${jsonEncode(map['errors'])}');
    }

    final data = map['data'] as Map<String, dynamic>?;

    final list = (data?[onlyUnread
                ? 'getUnreadNotifications'
                : 'getNotifications'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    final items = list.map(NotificationItem.fromJson).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // desc

    return items;
  }

  void close() => _client.close();
}
