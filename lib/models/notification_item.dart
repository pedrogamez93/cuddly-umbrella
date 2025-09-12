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

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      viewed: json['viewed'] as bool? ?? false,
      deleted: json['deleted'] as bool? ?? false,
      timestamp: DateTime.parse(json['timestamp'] as String),
      viewedAt: _parseDate(json['viewedAt']),
      deletedAt: _parseDate(json['deletedAt']),
    );
  }
}
