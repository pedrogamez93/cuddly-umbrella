import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/notification_item.dart';

class NotificationsApi {
  NotificationsApi({
    required this.endpoint, // p.ej. https://<appsync-id>.appsync-api.us-east-1.amazonaws.com/graphql
    required this.apiKey,   // da2-xxxx (QA según tu informe)
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String endpoint;
  final String apiKey;
  final http.Client _client;

  // ================= GraphQL =================

  // Queries (del informe)
  static const _qAll = r'''
    query GetNotifications($userEmail:String!){
      getNotifications(userEmail:$userEmail){
        id message title viewed viewedAt deleted deletedAt timestamp
      }
    }
  ''';

  static const _qUnread = r'''
    query GetUnreadNotifications($userEmail:String!){
      getUnreadNotifications(userEmail:$userEmail){
        id message title viewed viewedAt deleted deletedAt timestamp
      }
    }
  ''';

  // Mutations (del informe)
  static const _mMarkViewed = r'''
    mutation MarkNotificationAsViewed($notificationId: ID!) {
      markNotificationAsViewed(notificationId: $notificationId) {
        id viewed viewedAt title message deleted deletedAt timestamp
      }
    }
  ''';

  static const _mDelete = r'''
    mutation DeleteNotification($notificationId: ID!) {
      deleteNotification(notificationId: $notificationId) {
        id deleted deletedAt
      }
    }
  ''';

  static const _mMarkAllViewed = r'''
    mutation MarkAllNotificationsAsViewed($userEmail: String!) {
      markAllNotificationsAsViewed(userEmail: $userEmail) {
        id viewed viewedAt
      }
    }
  ''';

  static const _mMarkAllDeleted = r'''
    mutation MarkAllNotificationsAsDeleted($userEmail: String!) {
      markAllNotificationsAsDeleted(userEmail: $userEmail) {
        id deleted deletedAt
      }
    }
  ''';

  Future<Map<String, dynamic>> _postGraphQL({
    required String query,
    Map<String, dynamic>? variables,
    String? operationName,
  }) async {
    final resp = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
          },
          body: jsonEncode({
            if (operationName != null) 'operationName': operationName,
            'query': query,
            if (variables != null) 'variables': variables,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (resp.statusCode != 200) {
      throw Exception('AppSync ${resp.statusCode}: ${resp.body}');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['errors'] != null) {
      throw Exception('GraphQL errors: ${jsonEncode(map['errors'])}');
    }
    return (map['data'] as Map<String, dynamic>? ?? const {});
  }

  // ================ API Pública =================

  Future<List<NotificationItem>> fetch({
    required String userEmail,
    bool onlyUnread = false,
  }) async {
    final data = await _postGraphQL(
      query: onlyUnread ? _qUnread : _qAll,
      variables: {'userEmail': userEmail},
      operationName: onlyUnread ? 'GetUnreadNotifications' : 'GetNotifications',
    );

    final list = (data[onlyUnread ? 'getUnreadNotifications' : 'getNotifications'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    final items = list.map(NotificationItem.fromJson).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // desc
    return items;
  }

  Future<NotificationItem> markNotificationAsViewed(String id) async {
    final data = await _postGraphQL(
      query: _mMarkViewed,
      variables: {'notificationId': id},
      operationName: 'MarkNotificationAsViewed',
    );
    final node = (data['markNotificationAsViewed'] as Map<String, dynamic>);
    return NotificationItem.fromJson(node);
  }

  Future<void> deleteNotification(String id) async {
    await _postGraphQL(
      query: _mDelete,
      variables: {'notificationId': id},
      operationName: 'DeleteNotification',
    );
  }

  Future<void> markAllAsViewed(String userEmail) async {
    await _postGraphQL(
      query: _mMarkAllViewed,
      variables: {'userEmail': userEmail},
      operationName: 'MarkAllNotificationsAsViewed',
    );
  }

  Future<void> markAllAsDeleted(String userEmail) async {
    await _postGraphQL(
      query: _mMarkAllDeleted,
      variables: {'userEmail': userEmail},
      operationName: 'MarkAllNotificationsAsDeleted',
    );
  }

  void close() => _client.close();
}
