import 'dart:convert';

class NotificationItem {
  final String id;
  final String title;
  final String message;
  final bool viewed;
  final bool deleted;
  final DateTime timestamp;
  final DateTime? viewedAt;
  final DateTime? deletedAt;

  // Opcionales (si el backend los envía en algún flujo)
  final String? targetType;
  final String? targetId;
  final String? targetUrl;
  final Map<String, dynamic>? data;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.viewed,
    required this.deleted,
    required this.timestamp,
    this.viewedAt,
    this.deletedAt,
    this.targetType,
    this.targetId,
    this.targetUrl,
    this.data,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.trim().isEmpty) return null;
    return DateTime.tryParse(v.toString());
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y' || s == 'si' || s == 'sí';
    }
    return false;
  }

  static Map<String, dynamic>? _parseMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is String && v.trim().isNotEmpty) {
      try { return Map<String, dynamic>.from(jsonDecode(v)); } catch (_) {}
    }
    return null;
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      viewed: _toBool(json['viewed']),
      deleted: _toBool(json['deleted']),
      timestamp: DateTime.parse(json['timestamp'].toString()),
      viewedAt: _parseDate(json['viewedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      targetType: (json['targetType'] ?? json['target_type'])?.toString(),
      targetId: (json['targetId'] ?? json['target_id'] ?? '').toString().trim().isEmpty
          ? null
          : (json['targetId'] ?? json['target_id']).toString(),
      targetUrl: (json['targetUrl'] ?? json['target_url'])?.toString(),
      data: _parseMap(json['data']),
    );
  }

  NotificationItem copyWith({
    String? id,
    String? title,
    String? message,
    bool? viewed,
    bool? deleted,
    DateTime? timestamp,
    DateTime? viewedAt,
    DateTime? deletedAt,
    String? targetType,
    String? targetId,
    String? targetUrl,
    Map<String, dynamic>? data,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      viewed: viewed ?? this.viewed,
      deleted: deleted ?? this.deleted,
      timestamp: timestamp ?? this.timestamp,
      viewedAt: viewedAt ?? this.viewedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      targetUrl: targetUrl ?? this.targetUrl,
      data: data ?? this.data,
    );
  }
}
