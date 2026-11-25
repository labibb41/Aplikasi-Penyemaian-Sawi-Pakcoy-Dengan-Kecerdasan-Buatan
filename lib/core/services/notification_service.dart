import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (kIsWeb || _initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(settings: initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb || !_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'semaiku_actuator_channel',
      'Status Aktuator & Fuzzy',
      channelDescription: 'Notifikasi perubahan kipas, sprayer, dan lampu',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
  id: id,
  title: title,
  body: body,
  notificationDetails: details,
);
  }
}