class NotificationItem {
  final String id;
  final String title;
  final String message;
  final bool viewed;
  final bool deleted;
  final DateTime timestamp;
  final DateTime? viewedAt;
  final DateTime? deletedAt;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.viewed,
    required this.deleted,
    required this.timestamp,
    this.viewedAt,
    this.deletedAt,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.trim().isEmpty) return null;
    return DateTime.tryParse(v.toString());
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0; // 0/1
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y' || s == 'si' || s == 'sí';
    }
    return false;
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
    );
  }
}
