import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotifs {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await _plugin.initialize(init);

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> show({
    String? title,
    String? body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'somos_notif_channel',
        'Notificaciones Somos',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(0, title, body, details);
  }
}
