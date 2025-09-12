import 'package:flutter/material.dart';
import '../services/notifications_api.dart';
import '../models/notification_item.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/notifications_api.dart';

late final NotificationsApi _api = NotificationsApi(
  endpoint: dotenv.env['APPSYNC_HTTP_URL'] ?? '',
  apiKey: dotenv.env['APPSYNC_API_KEY'] ?? '',
);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.userEmail, this.onlyUnread = false});
  final String userEmail;
  final bool onlyUnread;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationsApi _api = NotificationsApi(
    endpoint: dotenv.env['APPSYNC_HTTP_URL'] ?? '',
    apiKey: dotenv.env['APPSYNC_API_KEY'] ?? '',
  );

  late Future<List<NotificationItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetch(
      userEmail: widget.userEmail,
      onlyUnread: widget.onlyUnread,
    );
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onlyUnread ? 'Notificaciones (no leídas)' : 'Notificaciones'),
      ),
      body: FutureBuilder<List<NotificationItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(child: Text('Sin notificaciones'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (_, i) {
              final n = items[i];
              return ListTile(
                leading: Icon(n.viewed ? Icons.notifications_none : Icons.notifications_active),
                title: Text(n.title.isEmpty ? '(Sin título)' : n.title),
                subtitle: Text(n.message),
                trailing: Text(
                  _fmt(n.timestamp),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: items.length,
          );
        },
      ),
    );
  }

  String _fmt(DateTime dt) {
    // formato corto yyyy-MM-dd HH:mm
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    // Si prefieres intl:
    // return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
  }
}
