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

  // Selecciones de campos
  static const _selectionBasic = r'''
    id message title viewed viewedAt deleted deletedAt timestamp
  ''';

  static const _selectionExt = r'''
    id message title viewed viewedAt deleted deletedAt timestamp
    targetType targetId targetUrl data
  ''';

  String _buildQuery({required bool unread, required bool extended}) => '''
    query ${unread ? 'GetUnreadNotifications' : 'GetNotifications'}(\$userEmail:String!){
      ${unread ? 'getUnreadNotifications' : 'getNotifications'}(userEmail:\$userEmail){
        ${extended ? _selectionExt : _selectionBasic}
      }
    }
  ''';

  String _buildMarkViewed({required bool extended}) => '''
    mutation MarkNotificationAsViewed(\$notificationId: ID!) {
      markNotificationAsViewed(notificationId: \$notificationId) {
        ${extended ? _selectionExt : _selectionBasic}
      }
    }
  ''';

  Future<Map<String, dynamic>> _postGraphQL({
    required String query,
    Map<String, dynamic>? variables,
    String? operationName,
  }) async {
    final resp = await _client.post(
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
    );

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['errors'] != null) {
      throw Exception('GraphQL errors: ${jsonEncode(map['errors'])}');
    }
    if (resp.statusCode != 200) {
      throw Exception('AppSync ${resp.statusCode}: ${resp.body}');
    }
    return (map['data'] as Map<String, dynamic>? ?? const {});
  }

  // ===== API pública con fallback =====

  Future<List<NotificationItem>> fetch({
    required String userEmail,
    bool onlyUnread = false,
  }) async {
    try {
      final dataExt = await _postGraphQL(
        query: _buildQuery(unread: onlyUnread, extended: true),
        variables: {'userEmail': userEmail},
        operationName:
            onlyUnread ? 'GetUnreadNotifications' : 'GetNotifications',
      );
      final key =
          onlyUnread ? 'getUnreadNotifications' : 'getNotifications';
      final list = (dataExt[key] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      final items = list.map(NotificationItem.fromJson).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    } catch (e) {
      // Si el esquema no soporta campos extendidos
      final msg = e.toString();
      if (!msg.contains('FieldUndefined')) rethrow;

      final dataBasic = await _postGraphQL(
        query: _buildQuery(unread: onlyUnread, extended: false),
        variables: {'userEmail': userEmail},
        operationName:
            onlyUnread ? 'GetUnreadNotifications' : 'GetNotifications',
      );
      final key =
          onlyUnread ? 'getUnreadNotifications' : 'getNotifications';
      final list = (dataBasic[key] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      final items = list.map(NotificationItem.fromJson).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    }
  }

  Future<NotificationItem> markNotificationAsViewed(String id) async {
    try {
      final dataExt = await _postGraphQL(
        query: _buildMarkViewed(extended: true),
        variables: {'notificationId': id},
        operationName: 'MarkNotificationAsViewed',
      );
      return NotificationItem.fromJson(
          (dataExt['markNotificationAsViewed'] as Map<String, dynamic>));
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('FieldUndefined')) rethrow;

      final dataBasic = await _postGraphQL(
        query: _buildMarkViewed(extended: false),
        variables: {'notificationId': id},
        operationName: 'MarkNotificationAsViewed',
      );
      return NotificationItem.fromJson(
          (dataBasic['markNotificationAsViewed'] as Map<String, dynamic>));
    }
  }

  // Otros
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
