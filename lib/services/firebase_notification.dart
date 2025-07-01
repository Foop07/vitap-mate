import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapmate/core/router/paths.dart';
import 'package:vitapmate/core/router/router.dart';
import 'package:vitapmate/features/social/presentation/providers/pocketbase.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'other_important',
    'others',
    description: 'This channel is used for  notifications.',
    importance: Importance.high,
    playSound: true,
  );
  static const AndroidNotificationChannel _chatChannel =
      AndroidNotificationChannel(
        'chat_messages',
        'chats',
        description: 'This channel is used chat notifications.',
        importance: Importance.high,
        playSound: true,
      );

  Future<void> initialize() async {
    await _initializeLocalNotifications();

    _setupFirebaseListeners();
  }

  Future<NotificationSettings> requestPermissions() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      announcement: true,
    );

    log('Notification permission status: ${settings.authorizationStatus}');
    return settings;
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_chatChannel);
  }

  void _setupFirebaseListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('📲 Foreground notification: ${message.notification?.title}');
      try {
        if (rootNavigatorKey.currentContext == null) return;
        String location =
            GoRouter.of(
              rootNavigatorKey.currentContext!,
            ).routeInformationProvider.value.uri.toString();
        if (!location.contains("social")) {
          showNotification(message);
        }
      } catch (e) {
        ();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log('Notification tapped: ${message.notification?.title}');
      _handleNotificationTap(message);
    });

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      log('FCM Token refreshed: $newToken');
      pbSetNtotification(tokenNew: newToken);
    });
  }

  Future<void> showNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;
    final channelId = message.notification?.android?.channelId ?? _channel.id;

    if (notification != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelId == _chatChannel.id ? _chatChannel.name : _channel.name,
            channelDescription:
                channelId == _chatChannel.id
                    ? _chatChannel.description
                    : _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data.toString(),
      );
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    log(' Local notification tapped: ${response.payload}');
    _navigateBasedOnPayload(response.payload);
  }

  void _handleNotificationTap(RemoteMessage message) {
    log(' Firebase notification tapped: ${message.data}');
    _navigateBasedOnData(message.data);
  }

  void _navigateBasedOnPayload(String? payload) {
    if (payload != null) {
      if (rootNavigatorKey.currentContext == null) return;
      GoRouter.of(rootNavigatorKey.currentContext!).goNamed(Paths.social);

      log('Navigating based on payload: $payload');
    }
  }

  void _navigateBasedOnData(Map<String, dynamic> data) {
    if (rootNavigatorKey.currentContext == null) return;
    GoRouter.of(rootNavigatorKey.currentContext!).goNamed(Paths.social);

    if (data.isNotEmpty) {
      log('Navigating based on data: $data');
    }
  }

  Future<String?> getToken() async {
    requestPermissions();
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      log(' Error getting token: $e');
      return null;
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}
