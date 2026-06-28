import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Must be top-level for the background isolate
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final notif = message.notification;
  if (notif != null) {
    await NotificationService._plugin.show(
      message.hashCode,
      notif.title ?? 'KidGuard Alert',
      notif.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'kidguard_alerts',
          'KidGuard Alerts',
          channelDescription: 'Health alerts and allergy warnings',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'kidguard_alerts';
  static const _channelName = 'KidGuard Alerts';
  static const _channelDesc = 'Health alerts and allergy warnings for your child';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDesc,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> initialize() async {
    if (kIsWeb) return;

    // Create the Android high-importance channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(initSettings);

    // Request FCM permission (Android 13+, iOS)
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('✓ FCM permission: ${settings.authorizationStatus}');

    // Show foreground FCM messages as local notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notif = message.notification;
      if (notif != null) {
        showAlert(
          title: notif.title ?? 'KidGuard Alert',
          body: notif.body ?? '',
          id: message.hashCode,
        );
      }
    });

    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('✓ FCM Token: $token');
  }

  /// Show a local notification immediately (works foreground + background).
  static Future<void> showAlert({
    required String title,
    required String body,
    int id = 0,
    bool severe = false,
  }) async {
    if (kIsWeb) return;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: severe ? Priority.max : Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }
}
