import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'notification_service.dart';

/// =========================
/// DATA MODEL
/// =========================

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String? imageUrl;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  bool isRead;
  final String type;
  bool isDeleted;
  final String source; // Track source: 'fcm', 'mysql', 'local'

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    required this.timestamp,
    required this.data,
    this.isRead = false,
    this.type = 'general',
    this.isDeleted = false,
    this.source = 'unknown',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'data': data,
      'isRead': isRead,
      'type': type,
      'isDeleted': isDeleted,
      'source': source,
    };
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      imageUrl: json['imageUrl'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      data: json['data'] != null ? Map<String, dynamic>.from(json['data']) : {},
      isRead: json['isRead'] ?? false,
      type: json['type'] ?? 'general',
      isDeleted: json['isDeleted'] ?? false,
      source: json['source'] ?? 'unknown',
    );
  }

  factory NotificationItem.fromFirebaseMessage(RemoteMessage message) {
    final imageUrl = message.data['image_url'] ??
        message.notification?.android?.imageUrl ??
        message.notification?.apple?.imageUrl ??
        message.data['image'];

    String title = message.data['title']?.toString() ?? '';
    String body = message.data['body']?.toString() ?? '';

    if (title.isEmpty) {
      title = message.notification?.title ?? '';
    }
    if (body.isEmpty) {
      body = message.notification?.body ?? '';
    }

    return NotificationItem(
      id: message.messageId ?? 'fcm_${DateTime.now().millisecondsSinceEpoch}',
      title: title.isNotEmpty ? title : 'إشعار جديد',
      body: body,
      imageUrl: imageUrl,
      timestamp: DateTime.now(),
      data: message.data,
      isRead: false,
      type: message.data['type'] ?? 'general',
      source: 'fcm',
    );
  }

  factory NotificationItem.fromMySQL(Map<String, dynamic> map) {
    Map<String, dynamic> payload = {};
    if (map['data_payload'] != null) {
      if (map['data_payload'] is String &&
          map['data_payload'].toString().isNotEmpty) {
        try {
          payload = jsonDecode(map['data_payload']);
        } catch (e) {
          // ignore
        }
      } else if (map['data_payload'] is Map) {
        payload = Map<String, dynamic>.from(map['data_payload']);
      }
    }

    return NotificationItem(
      id: map['id'].toString(),
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      imageUrl: map['image_url'],
      timestamp: DateTime.tryParse(map['sent_at'] ?? '') ?? DateTime.now(),
      data: payload,
      isRead: false,
      type: map['type'] ?? 'general',
      source: 'mysql',
    );
  }
}

/// =========================
/// NOTIFICATION MANAGER
/// =========================

class NotificationManager extends ChangeNotifier {
  static NotificationManager? _instance;
  static NotificationManager get instance =>
      _instance ??= NotificationManager._();

  NotificationManager._();

  List<NotificationItem> _notifications = [];
  int _unreadCount = 0;
  bool _isSyncing = false;
  Set<String> _deletedIds = {};
  Set<String> _processedMessageIds = {}; // Track processed FCM message IDs
  Set<String> _processedMySQLIds = {}; // Track processed MySQL IDs
  DateTime _lastSyncTime = DateTime.now().subtract(const Duration(minutes: 5));

  List<NotificationItem> get notifications =>
      List.unmodifiable(_notifications.where((n) => !n.isDeleted).toList());
  int get unreadCount => _unreadCount;
  bool get isSyncing => _isSyncing;

  static const String _storageKey = 'stored_notifications_final';
  static const String _deletedIdsKey = 'deleted_notification_ids';
  static const String _processedMessageIdsKey = 'processed_fcm_ids';
  static const String _processedMySQLIdsKey = 'processed_mysql_ids';

  /// FORCE LOAD FROM DISK
  Future<void> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // Load deleted IDs
      final deletedIdsStr = prefs.getString(_deletedIdsKey);
      if (deletedIdsStr != null) {
        _deletedIds = Set<String>.from(jsonDecode(deletedIdsStr));
      }

      // Load processed FCM IDs
      final processedFcmStr = prefs.getString(_processedMessageIdsKey);
      if (processedFcmStr != null) {
        _processedMessageIds = Set<String>.from(jsonDecode(processedFcmStr));
        // Keep only last 500 to prevent memory issues
        if (_processedMessageIds.length > 500) {
          _processedMessageIds = _processedMessageIds.skip(300).toSet();
        }
      }

      // Load processed MySQL IDs
      final processedMySqlStr = prefs.getString(_processedMySQLIdsKey);
      if (processedMySqlStr != null) {
        _processedMySQLIds = Set<String>.from(jsonDecode(processedMySqlStr));
        if (_processedMySQLIds.length > 500) {
          _processedMySQLIds = _processedMySQLIds.skip(300).toSet();
        }
      }

      // Load notifications
      final jsonStr = prefs.getString(_storageKey);

      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List;
        _notifications = list.map((e) => NotificationItem.fromJson(e)).toList();

        // Mark notifications as deleted if in deletedIds
        for (var notification in _notifications) {
          if (_deletedIds.contains(notification.id)) {
            notification.isDeleted = true;
          }
        }

        _sortAndCount();
        notifyListeners();
        debugPrint('📂 [Manager] Loaded ${_notifications.length} from disk');
      }
    } catch (e) {
      debugPrint('❌ [Manager] Load Error: $e');
    }
  }

  /// SYNC FROM SERVER AND DISK - COMPLETELY FIXED to prevent duplicates
  Future<void> fetchFromMySQL() async {
    // Prevent too frequent syncs
    if (DateTime.now().difference(_lastSyncTime).inSeconds < 30) {
      debugPrint('⏱️ [Manager] Skipping sync - too frequent');
      return;
    }

    if (_isSyncing) return;
    _isSyncing = true;
    _lastSyncTime = DateTime.now();
    Future.microtask(() => notifyListeners());

    try {
      final serverListRaw =
          await NotificationService.getAllNotifications(limit: 100);

      await loadNotifications();

      if (serverListRaw.isEmpty) {
        _isSyncing = false;
        notifyListeners();
        return;
      }

      final serverItems =
          serverListRaw.map((m) => NotificationItem.fromMySQL(m)).toList();

      final Map<String, NotificationItem> localMap = {
        for (var item in _notifications) item.id: item
      };

      bool hasChanges = false;
      int newItemsCount = 0;

      for (var serverItem in serverItems) {
        // Skip if this ID is deleted locally
        if (_deletedIds.contains(serverItem.id)) {
          continue;
        }

        // Skip if we've already processed this MySQL ID recently
        if (_processedMySQLIds.contains(serverItem.id)) {
          debugPrint(
              '⏭️ [Manager] Skipping already processed MySQL ID: ${serverItem.id}');
          continue;
        }

        if (localMap.containsKey(serverItem.id)) {
          final localItem = localMap[serverItem.id]!;
          // Update only if server item is newer and not deleted
          if (serverItem.timestamp.isAfter(localItem.timestamp) &&
              !localItem.isDeleted) {
            localMap[serverItem.id] = NotificationItem(
              id: serverItem.id,
              title: serverItem.title,
              body: serverItem.body,
              imageUrl: serverItem.imageUrl,
              timestamp: serverItem.timestamp,
              data: serverItem.data,
              type: serverItem.type,
              isRead: localItem.isRead,
              isDeleted: false,
              source: 'mysql',
            );
            hasChanges = true;
            debugPrint(
                '🔄 [Manager] Updated existing notification: ${serverItem.id}');
          }
        } else {
          // Check if this is a duplicate of an FCM notification
          bool isDuplicate = _notifications.any((n) =>
              n.title == serverItem.title &&
              n.body == serverItem.body &&
              (n.timestamp.difference(serverItem.timestamp).inSeconds < 10));

          if (!isDuplicate) {
            // New notification from server
            localMap[serverItem.id] = serverItem;
            _processedMySQLIds.add(serverItem.id);
            newItemsCount++;
            hasChanges = true;
            debugPrint('✅ [Manager] New MySQL notification: ${serverItem.id}');
          } else {
            debugPrint(
                '⏭️ [Manager] Skipping duplicate MySQL notification: ${serverItem.id}');
          }
        }
      }

      _notifications = localMap.values.toList();

      // Filter out deleted ones for sorting
      final activeNotifications =
          _notifications.where((n) => !n.isDeleted).toList();
      activeNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Rebuild list with active first, then deleted
      final deletedNotifications =
          _notifications.where((n) => n.isDeleted).toList();
      _notifications = [...activeNotifications, ...deletedNotifications];

      if (_notifications.length > 200) {
        _notifications = _notifications.take(200).toList();
      }

      _updateUnreadCount();

      if (hasChanges) {
        await _saveToDisk();
        debugPrint(
            '📦 [Manager] Saved ${newItemsCount} new notifications to disk');
      }
    } catch (e) {
      debugPrint('❌ [Manager] Sync Error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// ADD FIREBASE MESSAGE - COMPLETELY FIXED to prevent duplicates
  Future<void> addFirebaseMessage(RemoteMessage message) async {
    final messageId =
        message.messageId ?? 'fcm_${DateTime.now().millisecondsSinceEpoch}';

    // Check if we already processed this exact message ID
    if (_processedMessageIds.contains(messageId)) {
      debugPrint('⚠️ [Manager] Duplicate FCM message skipped (ID): $messageId');
      return;
    }

    final item = NotificationItem.fromFirebaseMessage(message);

    // Skip if this ID is deleted
    if (_deletedIds.contains(item.id)) {
      debugPrint('⚠️ [Manager] Skipping deleted notification: ${item.id}');
      _processedMessageIds.add(messageId);
      await _saveProcessedIds();
      return;
    }

    // Skip empty notifications
    if (item.title.isEmpty ||
        (item.title == 'إشعار جديد' && item.body.isEmpty)) {
      debugPrint('❌ [Manager] Skipping empty notification');
      _processedMessageIds.add(messageId);
      await _saveProcessedIds();
      return;
    }

    await loadNotifications();

    // Check for duplicates based on content similarity (not just ID)
    bool isDuplicate = false;

    // Check by exact ID first
    final existingById =
        _notifications.any((n) => n.id == item.id && !n.isDeleted);
    if (existingById) {
      isDuplicate = true;
      debugPrint('⚠️ [Manager] Duplicate by ID: ${item.id}');
    }

    // Check by content similarity (for cases where ID might be different)
    if (!isDuplicate) {
      for (var existing in _notifications) {
        if (!existing.isDeleted) {
          // Check if same title and body within 10 seconds
          if (existing.title == item.title &&
              existing.body == item.body &&
              existing.timestamp.difference(item.timestamp).inSeconds.abs() <
                  10) {
            isDuplicate = true;
            debugPrint('⚠️ [Manager] Duplicate by content: ${item.title}');
            break;
          }

          // Check if same ID pattern (FCM sometimes changes ID)
          if (existing.id
                  .contains(item.id.substring(0, min(20, item.id.length))) ||
              item.id.contains(
                  existing.id.substring(0, min(20, existing.id.length)))) {
            isDuplicate = true;
            debugPrint('⚠️ [Manager] Duplicate by ID pattern');
            break;
          }
        }
      }
    }

    if (isDuplicate) {
      _processedMessageIds.add(messageId);
      await _saveProcessedIds();
      return;
    }

    // Add new notification
    _notifications.insert(0, item);
    _processedMessageIds.add(messageId);
    _processedMySQLIds
        .add(item.id); // Also add to MySQL set to prevent future duplicates

    debugPrint('✅ [Manager] Added new notification: ${item.title}');

    _sortAndCount();
    await _saveToDisk();
    await _saveProcessedIds();
    notifyListeners();
  }

  int min(int a, int b) => a < b ? a : b;

  Future<void> markAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1 &&
        !_notifications[index].isRead &&
        !_notifications[index].isDeleted) {
      _notifications[index].isRead = true;
      _updateUnreadCount();
      await _saveToDisk();
      notifyListeners();

      // Optionally sync to server
      NotificationService.markAsRead(id);
    }
  }

  Future<void> markAllAsRead() async {
    bool changed = false;
    for (var n in _notifications) {
      if (!n.isRead && !n.isDeleted) {
        n.isRead = true;
        changed = true;
      }
    }
    if (changed) {
      _updateUnreadCount();
      await _saveToDisk();
      notifyListeners();
    }
  }

  /// DELETE NOTIFICATION
  Future<void> deleteNotification(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      // Mark as deleted
      _notifications[index].isDeleted = true;
      _deletedIds.add(id);

      _updateUnreadCount();
      await _saveToDisk();
      notifyListeners();
      debugPrint('🗑️ [Manager] Notification marked as deleted: $id');
    }
  }

  Future<void> clearAllNotifications() async {
    for (var notification in _notifications) {
      if (!notification.isDeleted) {
        notification.isDeleted = true;
        _deletedIds.add(notification.id);
      }
    }
    _updateUnreadCount();
    await _saveToDisk();
    notifyListeners();
    debugPrint('🗑️ [Manager] All notifications cleared');
  }

  List<NotificationItem> searchNotifications(String query) {
    if (query.isEmpty) return notifications;
    final q = query.toLowerCase();
    return notifications
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
  }

  void _sortAndCount() {
    // Sort only non-deleted notifications
    final activeNotifications =
        _notifications.where((n) => !n.isDeleted).toList();
    activeNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Rebuild list with active first, then deleted
    final deletedNotifications =
        _notifications.where((n) => n.isDeleted).toList();
    _notifications = [...activeNotifications, ...deletedNotifications];

    _updateUnreadCount();
  }

  void _updateUnreadCount() {
    _unreadCount =
        _notifications.where((n) => !n.isRead && !n.isDeleted).length;
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // Save notifications
      final jsonStr =
          jsonEncode(_notifications.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);

      // Save deleted IDs
      await prefs.setString(_deletedIdsKey, jsonEncode(_deletedIds.toList()));

      debugPrint(
          '💾 [Manager] Saved to disk. Total: ${_notifications.length}, Deleted: ${_deletedIds.length}');
    } catch (e) {
      debugPrint('❌ [Manager] Save Error: $e');
    }
  }

  Future<void> _saveProcessedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save processed FCM IDs
      await prefs.setString(
          _processedMessageIdsKey, jsonEncode(_processedMessageIds.toList()));

      // Save processed MySQL IDs
      await prefs.setString(
          _processedMySQLIdsKey, jsonEncode(_processedMySQLIds.toList()));

      debugPrint(
          '💾 [Manager] Saved processed IDs. FCM: ${_processedMessageIds.length}, MySQL: ${_processedMySQLIds.length}');
    } catch (e) {
      debugPrint('❌ [Manager] Save Processed IDs Error: $e');
    }
  }

  /// Clear old processed IDs periodically
  void cleanOldProcessedIds() {
    if (_processedMessageIds.length > 500) {
      _processedMessageIds = _processedMessageIds.skip(300).toSet();
    }
    if (_processedMySQLIds.length > 500) {
      _processedMySQLIds = _processedMySQLIds.skip(300).toSet();
    }
    _saveProcessedIds();
  }
}

/// =========================
/// LOCAL NOTIFICATION SERVICE
/// =========================
class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static void initialize() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint('🔔 Local Notification Tapped (Foreground)');
        _navigateToNotifications();
      },
    );
  }

  static void showNotification(RemoteMessage message) async {
    if (!Platform.isAndroid) return;

    try {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );
      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await _notificationsPlugin.show(
        id: id,
        title: message.notification?.title ?? 'إشعار جديد',
        body: message.notification?.body ?? '',
        notificationDetails: platformChannelSpecifics,
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
    }
  }
}

void _navigateToNotifications() async {
  await NotificationManager.instance.loadNotifications();

  if (navigatorKey.currentState != null) {
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (context) => const NotificationsScreen()),
    );
  } else {
    Future.delayed(const Duration(milliseconds: 500), () {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
      );
    });
  }
}

/// =========================
/// FCM BACKGROUND HANDLER - FIXED
/// =========================

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🌙 [BG] Message Received: ${message.messageId}');

  final hasTitle = (message.data['title']?.toString() ?? '').isNotEmpty ||
      (message.notification?.title ?? '').isNotEmpty;
  final hasBody = (message.data['body']?.toString() ?? '').isNotEmpty ||
      (message.notification?.body ?? '').isNotEmpty;

  if (!hasTitle && !hasBody) {
    debugPrint('🌙 [BG] Skipping empty notification - no title or body');
    return;
  }

  final item = NotificationItem.fromFirebaseMessage(message);

  if (item.title.isEmpty || (item.title == 'إشعار جديد' && item.body.isEmpty)) {
    debugPrint('🌙 [BG] Skipping notification with default/empty title');
    return;
  }

  // Check if this notification was deleted before saving
  final prefs = await SharedPreferences.getInstance();

  // Check deleted IDs
  final deletedIdsStr = prefs.getString('deleted_notification_ids');
  if (deletedIdsStr != null) {
    final deletedIds = Set<String>.from(jsonDecode(deletedIdsStr));
    if (deletedIds.contains(item.id)) {
      debugPrint('🌙 [BG] Skipping deleted notification: ${item.id}');
      return;
    }
  }

  // Check processed FCM IDs to avoid duplicates in background
  final processedFcmStr = prefs.getString('processed_fcm_ids');
  if (processedFcmStr != null) {
    final processedIds = Set<String>.from(jsonDecode(processedFcmStr));
    if (processedIds.contains(message.messageId)) {
      debugPrint(
          '🌙 [BG] Skipping already processed FCM message: ${message.messageId}');
      return;
    }
  }

  await NotificationService.saveToLocalDisk(item.toJson());
  debugPrint('🌙 [BG] Notification Saved to Disk: ${item.title}');
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// =========================
/// MAIN & NAVIGATION LOGIC
/// =========================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar_IQ', null);

  try {
    await Firebase.initializeApp();

    LocalNotificationService.initialize();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationManager.instance.loadNotifications();

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    await messaging.subscribeToTopic('all_employees');

    if (Platform.isAndroid) {
      await _requestIgnoreBatteryOptimizations();
    }

    await _setupNotificationNavigation(messaging);

    // Clean old processed IDs periodically
    Timer.periodic(const Duration(hours: 1), (_) {
      NotificationManager.instance.cleanOldProcessedIds();
    });
  } catch (e) {
    debugPrint('❌ Init Error: $e');
  }

  runApp(const MyApp());
}

Future<void> _requestIgnoreBatteryOptimizations() async {
  try {
    var status = await Permission.ignoreBatteryOptimizations.status;
    if (!status.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  } catch (e) {
    debugPrint('⚠️ Battery optimization request failed: $e');
  }
}

Future<void> _setupNotificationNavigation(FirebaseMessaging messaging) async {
  try {
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🚀 [Launch] App opened from Terminated via Notification');
      await NotificationManager.instance.addFirebaseMessage(initialMessage);
      Future.delayed(const Duration(seconds: 2), () {
        _navigateToNotifications();
      });
    }
  } catch (e) {
    debugPrint('Error getting initial message: $e');
  }

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    debugPrint('👆 [Click] App opened from Background via Notification');
    await NotificationManager.instance.addFirebaseMessage(message);
    _navigateToNotifications();
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('🌞 [FG] Notification received while app is open');
    NotificationManager.instance.addFirebaseMessage(message);
    if (message.notification != null) {
      LocalNotificationService.showNotification(message);
    }
  });
}

/// =========================
/// THEME & UI
/// =========================

final ThemeData appTheme = ThemeData(
  primarySwatch: Colors.teal,
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF00BFA5),
    brightness: Brightness.light,
  ),
  textTheme: TextTheme(
    displayLarge: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    titleLarge: GoogleFonts.cairo(fontWeight: FontWeight.w600),
    bodyLarge: GoogleFonts.cairo(),
    bodyMedium: GoogleFonts.cairo(),
    labelLarge: GoogleFonts.cairo(fontWeight: FontWeight.w500),
  ),
  appBarTheme: AppBarTheme(
    centerTitle: true,
    backgroundColor: const Color(0xFF00BFA5),
    foregroundColor: Colors.white,
    titleTextStyle: GoogleFonts.cairo(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  ),
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [Lifecycle] App Resumed - Syncing notifications...');
      NotificationManager.instance.loadNotifications().then((_) {
        // Don't auto-sync on resume to prevent duplicates
        // NotificationManager.instance.fetchFromMySQL();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الشركة العامة لتعبئة وخدمات الغاز',
      theme: appTheme,
      locale: const Locale('ar', 'IQ'),
      builder: (context, child) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: child!,
        );
      },
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
    );
  }
}

// --------------------------------------------------------
// UI COMPONENTS
// --------------------------------------------------------

class ModernCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final List<BoxShadow>? boxShadow;

  const ModernCard({
    Key? key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 20,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.boxShadow,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
      ),
      child: child,
    );
  }
}

class ModernButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final Color? color;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool isGradient;

  const ModernButton({
    Key? key,
    required this.onPressed,
    required this.child,
    this.color,
    this.height = 56,
    this.borderRadius = 15,
    this.padding = EdgeInsets.zero,
    this.isGradient = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Ink(
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: isGradient
                  ? LinearGradient(
                      colors: [
                        color ?? const Color(0xFF00BFA5),
                        color != null
                            ? color!.withOpacity(0.8)
                            : const Color(0xFF00A896),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isGradient ? null : (color ?? const Color(0xFF00BFA5)),
              boxShadow: [
                BoxShadow(
                  color: (color ?? const Color(0xFF00BFA5)).withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(child: child),
          ),
        ));
  }
}

class NotificationIcon extends StatelessWidget {
  final VoidCallback onTap;

  const NotificationIcon({Key? key, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationManager.instance,
      builder: (context, child) {
        final count = NotificationManager.instance.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                size: 28,
                color: Colors.white,
              ),
              onPressed: onTap,
              tooltip: 'الإشعارات',
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// --------------------------------------------------------
// SCREENS
// --------------------------------------------------------

class NotificationDetailScreen extends StatelessWidget {
  final NotificationItem notification;

  const NotificationDetailScreen({Key? key, required this.notification})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'تفاصيل الإشعار',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title,
              style: GoogleFonts.cairo(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(notification.timestamp),
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getNotificationColor(notification.type)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getNotificationTypeLabel(notification.type),
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _getNotificationColor(notification.type),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            if (notification.imageUrl != null &&
                notification.imageUrl!.isNotEmpty)
              Column(
                children: [
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[100],
                    ),
                    child: _buildNotificationImage(notification.imageUrl!),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            Text(
              notification.body,
              textAlign: TextAlign.justify,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                height: 1.6,
                color: const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(height: 32),
            // Show only the company name - NO data payload display
            Text(
              'الشركة العامة لتعبئة وخدمات الغاز',
              style: GoogleFonts.cairo(
                fontSize: 10,
                color: const Color(0xFF2D3748),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationImage(String imageUrl) {
    try {
      Uri uri = Uri.parse(imageUrl);

      if (!uri.hasScheme) {
        uri = Uri.parse('https://$imageUrl');
      }

      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: uri.toString(),
            width: double.infinity,
            height: 250,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00BFA5),
                ),
              ),
            ),
            errorWidget: (context, url, error) {
              return Container(
                color: Colors.grey[100],
                child: Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey[400],
                    size: 50,
                  ),
                ),
              );
            },
          ),
        );
      } else {
        return _buildFallbackImage();
      }
    } catch (e) {
      return _buildFallbackImage();
    }
  }

  Widget _buildFallbackImage() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.grey[400],
          size: 50,
        ),
      ),
    );
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'salary':
        return Colors.green;
      case 'announcement':
        return Colors.blue;
      case 'department':
        return Colors.orange;
      case 'test':
        return Colors.purple;
      default:
        return const Color(0xFF00BFA5);
    }
  }

  String _getNotificationTypeLabel(String type) {
    switch (type) {
      case 'salary':
        return 'راتب';
      case 'announcement':
        return 'إعلان';
      case 'department':
        return 'قسم';
      case 'test':
        return 'اختبار';
      default:
        return 'عام';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    try {
      final dateFormat = DateFormat('yyyy-MM-dd HH:mm', 'ar_IQ');
      return dateFormat.format(timestamp);
    } catch (e) {
      return '${timestamp.year}-${timestamp.month}-${timestamp.day} ${timestamp.hour}:${timestamp.minute}';
    }
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.9, curve: Curves.easeOutBack),
    );

    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PrivacyPolicyScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE8F5F3),
              Color(0xFFD4EDE9),
              Color(0xFFC0E5DF),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -100,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00BFA5).withOpacity(0.15),
                  ),
                ),
              ),
            ),
            Center(
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(_slideAnimation),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ModernCard(
                    width: MediaQuery.of(context).size.width * 0.85,
                    padding: const EdgeInsets.all(40),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 140,
                            height: 140,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BFA5),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF00BFA5).withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.business,
                                  size: 80,
                                  color: Colors.white,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          'الشركة العامة لتعبئة',
                          style: GoogleFonts.cairo(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D3748),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          'وخدمات الغاز',
                          style: GoogleFonts.cairo(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D3748),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 15),
                        Text(
                          'بوابة الموظف الرقمية',
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF00BFA5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF00BFA5),
                            ),
                            strokeWidth: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.only(top: 60, bottom: 30, left: 20, right: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF00BFA5),
                  Color(0xFF00A896),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00BFA5).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  size: 50,
                  color: Colors.white,
                ),
                const SizedBox(height: 15),
                Text(
                  'سياسة الخصوصية',
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ModernCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPrivacySection(
                      '1. المقدمة',
                      'تحترم الشركة العامة لتعبئة وخدمات الغاز خصوصية موظفيها وتلتزم بحماية بياناتهم الشخصية. توضح هذه السياسة كيفية جمع واستخدام وحماية المعلومات الخاصة بالموظفين.',
                    ),
                    _buildPrivacySection(
                      '2. البيانات المجمعة',
                      'يتم جمع البيانات الأساسية للموظف مثل الاسم، الرقم الوظيفي، القسم، الراتب، والمعلومات الوظيفية الأخرى اللازمة لإدارة الموارد البشرية والرواتب.',
                    ),
                    _buildPrivacySection(
                      '3. استخدام البيانات',
                      'تُستخدم البيانات لأغراض إدارية فقط، مثل حساب الرواتب، إدارة الحضور والانصراف، والتواصل مع الموظفين بخصوص الأمور الوظيفية.',
                    ),
                    _buildPrivacySection(
                      '4. حماية البيانات',
                      'تتخذ الشركة العامة لتعبئة وخدمات الغاز جميع التدبير الأمنية اللازمة لحماية بيانات الموظفين من الوصول غير المصرح به أو الكشف عنها.',
                    ),
                    _buildPrivacySection(
                      '5. مشاركة البيانات',
                      'لن يتم مشاركة بيانات الموظفين مع أي جهة خارجية إلا في حالات ضرورية مثل الامتثال للقوانين أو بموافقة الموظف.',
                    ),
                    _buildPrivacySection(
                      '6. الاحتفاظ بالبيانات',
                      'سيتم الاحتفاظ ببيانات الموظفين طوال فترة عملهم في الشركة، وبعد انتهاء الخدمة، سيتم حظها وفقًا للمتطلبات القانونية.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ModernButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const WebViewScreen(),
                  ),
                );
              },
              child: Text(
                'موافق',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySection(String title, String content) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00BFA5),
                ),
              ),
            ),
            Text(
              content,
              style: GoogleFonts.cairo(
                fontSize: 15,
                height: 1.6,
                color: const Color(0xFF4A5568),
              ),
              textAlign: TextAlign.right,
            ),
          ],
        ));
  }
}

// Notifications Screen - FIXED
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all';
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationManager.instance.loadNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [UI] Resumed Notifications Screen - Refreshing');
      NotificationManager.instance.loadNotifications();
    }
  }

  Future<void> _refreshNotifications() async {
    setState(() {
      _isRefreshing = true;
    });

    await NotificationManager.instance.fetchFromMySQL();

    setState(() {
      _isRefreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('الإشعارات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'mark_all_read':
                  await NotificationManager.instance.markAllAsRead();
                  break;
                case 'clear_all':
                  bool? confirm = await _showDeleteConfirmDialog();
                  if (confirm == true) {
                    await NotificationManager.instance.clearAllNotifications();
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mark_all_read',
                child: Row(
                  children: [
                    const Icon(Icons.done_all, color: Color(0xFF00BFA5)),
                    const SizedBox(width: 8),
                    Text('تحديد الكل كمقروء', style: GoogleFonts.cairo()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    const Icon(Icons.delete_sweep, color: Colors.red),
                    const SizedBox(width: 8),
                    Text('حذف جميع الإشعارات', style: GoogleFonts.cairo()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'البحث في الإشعارات...',
                    hintStyle: GoogleFonts.cairo(color: Colors.grey[600]),
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFF00BFA5)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF00BFA5)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'الكل'),
                      const SizedBox(width: 8),
                      _buildFilterChip('salary', 'الرواتب'),
                      const SizedBox(width: 8),
                      _buildFilterChip('announcement', 'الإعلانات'),
                      const SizedBox(width: 8),
                      _buildFilterChip('department', 'الأقسام'),
                      const SizedBox(width: 8),
                      _buildFilterChip('general', 'عامة'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isRefreshing)
            const LinearProgressIndicator(
                color: Color(0xFF00BFA5), minHeight: 2),
          Expanded(
            child: AnimatedBuilder(
              animation: NotificationManager.instance,
              builder: (context, child) {
                List<NotificationItem> filteredNotifications =
                    _getFilteredNotifications();

                if (filteredNotifications.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: _refreshNotifications,
                  color: const Color(0xFF00BFA5),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredNotifications.length,
                    itemBuilder: (context, index) {
                      NotificationItem notification =
                          filteredNotifications[index];
                      return _buildNotificationCard(notification);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    bool isSelected = _selectedFilter == value;

    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.cairo(
          color: isSelected ? Colors.white : const Color(0xFF00BFA5),
          fontWeight: FontWeight.w500,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = selected ? value : 'all';
        });
      },
      selectedColor: const Color(0xFF00BFA5),
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: const Color(0xFF00BFA5),
        width: isSelected ? 0 : 1,
      ),
    );
  }

  List<NotificationItem> _getFilteredNotifications() {
    List<NotificationItem> notifications =
        NotificationManager.instance.notifications;

    if (_selectedFilter != 'all') {
      notifications =
          notifications.where((n) => n.type == _selectedFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      notifications =
          NotificationManager.instance.searchNotifications(_searchQuery);
      if (_selectedFilter != 'all') {
        notifications =
            notifications.where((n) => n.type == _selectedFilter).toList();
      }
    }

    return notifications;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF00BFA5).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              size: 60,
              color: Color(0xFF00BFA5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _searchQuery.isNotEmpty ? 'لا توجد نتائج للبحث' : 'لا توجد إشعارات',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'جرب البحث بكلمات أخرى'
                : 'ستظهر الإشعارات الجديدة هنا',
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(NotificationItem notification) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        return await _showDeleteConfirmDialog(single: true);
      },
      onDismissed: (direction) async {
        await NotificationManager.instance.deleteNotification(notification.id);
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: notification.isRead ? 1 : 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: notification.isRead
              ? BorderSide.none
              : const BorderSide(color: Color(0xFF00BFA5), width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (!notification.isRead) {
              await NotificationManager.instance.markAsRead(notification.id);
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NotificationDetailScreen(
                  notification: notification,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getNotificationColor(notification.type)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getNotificationIcon(notification.type),
                    color: _getNotificationColor(notification.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: notification.isRead
                                    ? FontWeight.w500
                                    : FontWeight.bold,
                                color: notification.isRead
                                    ? const Color(0xFF4A5568)
                                    : const Color(0xFF2D3748),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!notification.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00BFA5),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTimestamp(notification.timestamp),
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getNotificationColor(notification.type)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getNotificationTypeLabel(notification.type),
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _getNotificationColor(notification.type),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (notification.imageUrl != null &&
                          notification.imageUrl!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[100],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _buildNotificationImageInList(
                                notification.imageUrl!),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationImageInList(String imageUrl) {
    try {
      Uri uri = Uri.parse(imageUrl);

      if (!uri.hasScheme) {
        uri = Uri.parse('https://$imageUrl');
      }

      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return CachedNetworkImage(
          imageUrl: uri.toString(),
          width: double.infinity,
          height: 120,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFF00BFA5)),
              ),
            ),
          ),
          errorWidget: (context, url, error) {
            return Container(
              color: Colors.grey[100],
              child: Center(
                child: Icon(
                  Icons.broken_image,
                  color: Colors.grey[400],
                  size: 32,
                ),
              ),
            );
          },
        );
      } else {
        return Container(
          color: Colors.grey[100],
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: Colors.grey[400],
              size: 32,
            ),
          ),
        );
      }
    } catch (e) {
      return Container(
        color: Colors.grey[100],
        child: Center(
          child: Icon(
            Icons.broken_image,
            color: Colors.grey[400],
            size: 32,
          ),
        ),
      );
    }
  }

  Future<bool?> _showDeleteConfirmDialog({bool single = false}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.delete_outline,
              color: Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              single ? 'حذف الإشعار' : 'حذف جميع الإشعارات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          single
              ? 'هل تريد حذف هذا الإشعار؟'
              : 'هل تريد حذف جميع الإشعارات؟ لا يمكن التراجع عن هذا الإجراء.',
          style: GoogleFonts.cairo(
            fontSize: 16,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'حذف',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'salary':
        return Colors.green;
      case 'announcement':
        return Colors.blue;
      case 'department':
        return Colors.orange;
      case 'test':
        return Colors.purple;
      default:
        return const Color(0xFF00BFA5);
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'salary':
        return Icons.attach_money;
      case 'announcement':
        return Icons.campaign;
      case 'department':
        return Icons.business;
      case 'test':
        return Icons.science;
      default:
        return Icons.notifications;
    }
  }

  String _getNotificationTypeLabel(String type) {
    switch (type) {
      case 'salary':
        return 'راتب';
      case 'announcement':
        return 'إعلان';
      case 'department':
        return 'قسم';
      case 'test':
        return 'اختبار';
      default:
        return 'عام';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    try {
      DateTime now = DateTime.now();
      Duration difference = now.difference(timestamp);

      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inHours < 1) {
        return 'منذ ${difference.inMinutes} دقيقة';
      } else if (difference.inDays < 1) {
        return 'منذ ${difference.inHours} ساعة';
      } else if (difference.inDays < 7) {
        return 'منذ ${difference.inDays} يوم';
      } else {
        final dateFormat = DateFormat('dd/MM/yyyy', 'ar_IQ');
        return dateFormat.format(timestamp);
      }
    } catch (e) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  static const MethodChannel _channel = MethodChannel('snap_webview');

  final String loginUrl = 'https://gate.scgfs-oil.gov.iq/login';
  WebViewController? controller;
  bool isLoading = true;
  double loadingProgress = 0.0;
  bool canGoBack = false;
  bool hasError = false;
  String errorMessage = '';
  String currentUrl = '';
  bool isLoggedIn = false;
  bool isOnLoginPage = true;
  String lastNavigatedUrl = '';
  int navigationCount = 0;
  double zoomLevel = 1.0;

  final GlobalKey _webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _initializeWebView();
      }
    });
  }

  void _initializeWebView() {
    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: (JavaScriptMessage message) {
            debugPrint('📨 JavaScript message received: ${message.message}');
          },
        );

      if (Platform.isAndroid) {
        final androidController =
            controller!.platform as AndroidWebViewController;
        androidController.setMediaPlaybackRequiresUserGesture(false);
        controller!.enableZoom(true);
      }

      controller!.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('🔄 Page started loading: $url');

            if (!url.contains('download=1')) {
              navigationCount = 0;
              lastNavigatedUrl = '';
            }

            if (mounted) {
              setState(() {
                isLoading = true;
                hasError = false;
                loadingProgress = 0.0;
                currentUrl = url;
                isLoggedIn = !url.contains('/login');
              });
            }

            if (Platform.isAndroid) {
              Future.delayed(const Duration(milliseconds: 500), () {
                _injectAndroidFix();
              });
            }
          },
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                loadingProgress = progress / 100;
              });
            }
          },
          onPageFinished: (String url) {
            debugPrint('✅ Page finished loading: $url');
            navigationCount = 0;

            if (mounted) {
              setState(() {
                isLoading = false;
                loadingProgress = 1.0;
                currentUrl = url;
                isLoggedIn = !url.contains('/login');
                isOnLoginPage = url.contains('/login');
              });
            }
            _updateCanGoBack();

            if (url.contains('/login')) {
              _hideNotificationsOnLoginPage();
            }

            if (url.contains('.html')) {
              setState(() {
                zoomLevel = 1.0;
              });
              _autoFitPageToScreen();
            }

            if (Platform.isAndroid) {
              _injectAndroidFix();
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ WebView Error: ${error.description}');

            if (mounted) {
              setState(() {
                isLoading = false;
                hasError = true;
                errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.contains('download=1')) {
              String cleanUrl =
                  request.url.replaceAll(RegExp(r'[?&]download=1'), '');

              if (cleanUrl != currentUrl) {
                controller?.loadRequest(Uri.parse(cleanUrl));
                return NavigationDecision.prevent;
              }
            }

            if (request.url == lastNavigatedUrl) {
              navigationCount++;
              if (navigationCount > 5) {
                return NavigationDecision.prevent;
              }
            } else {
              lastNavigatedUrl = request.url;
              navigationCount = 1;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

      controller!.loadRequest(Uri.parse(loginUrl));

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Error initializing WebView: $e');
      if (mounted) {
        setState(() {
          hasError = true;
          errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _updateCanGoBack() async {
    if (controller != null) {
      final canNavigateBack = await controller!.canGoBack();
      setState(() {
        canGoBack = canNavigateBack;
      });
    }
  }

  Future<void> _autoFitPageToScreen() async {
    if (controller == null) return;

    try {
      await controller!.runJavaScript('''
        (function() {
          var existingViewports = document.querySelectorAll('meta[name="viewport"]');
          existingViewports.forEach(function(viewport) {
            viewport.remove();
          });
          
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes, shrink-to-fit=yes';
          document.getElementsByTagName('head')[0].appendChild(meta);
          
          document.body.style.margin = '0';
          document.body.style.padding = '8px';
          document.body.style.boxSizing = 'border-box';
          document.body.style.overflow = 'auto';
          document.body.style.width = '100%';
        })();
      ''');
    } catch (e) {
      debugPrint('⚠️ Error auto-fitting page: $e');
    }
  }

  void _zoomIn() {
    if (zoomLevel < 3.0) {
      setState(() {
        zoomLevel += 0.2;
      });
      _applyZoom();
    }
  }

  void _zoomOut() {
    if (zoomLevel > 0.5) {
      setState(() {
        zoomLevel -= 0.2;
      });
      _applyZoom();
    }
  }

  Future<void> _applyZoom() async {
    if (controller == null) return;
    try {
      await controller!.runJavaScript('''
          (function() {
            var html = document.documentElement;
            var body = document.body;
            html.style.transformOrigin = '0 0';
            body.style.transformOrigin = '0 0';
            html.style.transform = 'scale($zoomLevel)';
            html.style.width = (100 / $zoomLevel) + '%';
          })();
        ''');
    } catch (e) {
      debugPrint('❌ Error applying zoom: $e');
    }
  }

  Future<void> _hideNotificationsOnLoginPage() async {
    if (controller == null) return;
    try {
      await controller!.runJavaScript('''
        (function() {
          var notifications = document.querySelectorAll('.alert, .notification, .toast, [role="alert"], .flash-message, .alert-success, .alert-danger, .alert-warning, .alert-info');
          notifications.forEach(function(notif) {
            notif.style.display = 'none';
          });
        })();
      ''');
    } catch (e) {
      debugPrint('⚠️ Error hiding notifications: $e');
    }
  }

  Future<void> _injectAndroidFix() async {
    if (controller == null) return;

    const String jsCode = '''
      (function() {
        if (window.androidFixInjected) { return; }
        window.androidFixInjected = true;
        
        var originalOpen = window.open;
        window.open = function(url, name, specs) {
          if (url && url.indexOf('download=1') !== -1) {
            var cleanUrl = url.replace(/[?&]download=1/g, '');
            window.location.href = cleanUrl;
            return window;
          }
          return originalOpen.call(window, url, name, specs);
        };
      })();
    ''';

    try {
      await controller!.runJavaScript(jsCode);
    } catch (e) {
      debugPrint('❌ Error injecting JavaScript: $e');
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 29) {
          return true;
        }

        final status = await Permission.storage.status;
        if (status.isGranted) return true;

        final result = await Permission.storage.request();
        return result.isGranted;
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  Future<Uint8List> _captureWebView() async {
    if (Platform.isIOS) {
      final bytes = await _channel.invokeMethod('takeSnapshot');
      return Uint8List.fromList(List<int>.from(bytes));
    }

    RenderRepaintBoundary boundary =
        _webViewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image img = await boundary.toImage(pixelRatio: 6.0);
    ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _savePageAsImage() async {
    try {
      bool hasPermission = await _requestPermissions();
      if (!hasPermission) {
        _showMessage('الرجاء منح صلاحة الوصول للصور');
        return;
      }

      if (mounted) setState(() => isLoading = true);
      await Future.delayed(const Duration(milliseconds: 1000));

      Uint8List screenshot;
      try {
        screenshot = await _captureWebView();
      } catch (e) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'salary_slip_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(screenshot);

      try {
        await Gal.putImage(tempFile.path, album: 'قسائم الرواتب');
        if (mounted) setState(() => isLoading = false);
        _showMessage('تم الحفظ في معرض الصور');

        await Future.delayed(const Duration(seconds: 1), () async {
          try {
            await tempFile.delete();
          } catch (e) {}
        });
      } catch (e) {
        if (mounted) setState(() => isLoading = false);
        _showMessage('فشل حفظ الصورة في المعرض');
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showMessage('حدث خطأ أثناء حفظ الصورة');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        backgroundColor: const Color(0xFF00BFA5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _shouldShowButtons() {
    debugPrint('🔍 Checking URL for buttons: $currentUrl');

    if (currentUrl == 'https://gate.scgfs-oil.gov.iq/payslip.html' ||
        currentUrl == 'https://gate.scgfs-oil.gov.iq/payslips' ||
        currentUrl == 'https://gate.scgfs-oil.gov.iq/salary' ||
        currentUrl.contains('/dashboard') ||
        currentUrl.contains('/admin') ||
        currentUrl.contains('/info') ||
        currentUrl.contains('/profile') ||
        currentUrl.contains('/personal') ||
        currentUrl.contains('/employee') ||
        currentUrl.contains('/user') ||
        currentUrl.contains('/data') ||
        currentUrl.contains('/settings')) {
      debugPrint('🚫 This is main list page or admin page - hiding buttons');
      return false;
    }

    bool hasParameter = currentUrl.contains('?') ||
        currentUrl.contains('/view/') ||
        (currentUrl.contains('.html') &&
            currentUrl.split('/').last.length > 15);

    bool isDifferentFromMain = currentUrl.contains('.html') &&
        currentUrl != 'https://gate.scgfs-oil.gov.iq/payslip.html';

    bool shouldShow = hasParameter || isDifferentFromMain;

    debugPrint(
        '🎯 Should show buttons: $shouldShow (hasParameter: $hasParameter, isDifferentFromMain: $isDifferentFromMain)');
    return shouldShow;
  }

  Future<bool> _onWillPop() async {
    if (canGoBack && controller != null) {
      controller!.goBack();
      return false;
    }
    return await _showExitDialog() ?? false;
  }

  Future<bool?> _showExitDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BFA5).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.logout,
                      size: 48,
                      color: Color(0xFF00BFA5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'الخروج من التطبيق',
                    style: GoogleFonts.cairo(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'هل تريد الخروج من التطبيق؟',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                            if (Platform.isAndroid) {
                              SystemNavigator.pop();
                            } else if (Platform.isIOS) {
                              exit(0);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFA5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'نعم',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black54,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                                color: Colors.grey.shade300, width: 1.5),
                          ),
                          child: Text(
                            'لا',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (canGoBack && controller != null) {
                controller!.goBack();
              } else {
                final shouldExit = await _showExitDialog();
                if (shouldExit == true) SystemNavigator.pop();
              }
            },
          ),
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'الشركة العامة لتعبئة وخدمات الغاز',
              style:
                  GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          actions: [
            if (!isOnLoginPage)
              NotificationIcon(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const NotificationsScreen()),
                  );
                },
              ),
          ],
        ),
        body: Stack(
          children: [
            if (controller != null && !hasError)
              RepaintBoundary(
                key: _webViewKey,
                child: Container(
                  color: Colors.white,
                  child: WebViewWidget(controller: controller!),
                ),
              ),
            if (hasError)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 60, color: Colors.red),
                    const SizedBox(height: 15),
                    Text('خطأ في الاتصال',
                        style: GoogleFonts.cairo(fontSize: 18)),
                    Text(errorMessage,
                        style: GoogleFonts.cairo(fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ModernButton(
                      onPressed: () {
                        setState(() => hasError = false);
                        _initializeWebView();
                      },
                      child: Text('إعادة المحاولة',
                          style: GoogleFonts.cairo(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            if (isLoading && !hasError)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: ModernCard(
                    width: 220,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: loadingProgress > 0 ? loadingProgress : null,
                          color: const Color(0xFF00BFA5),
                        ),
                        const SizedBox(height: 20),
                        Text('جاري التحميل...', style: GoogleFonts.cairo()),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: _shouldShowButtons()
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: 'zoom_out',
                    mini: true,
                    onPressed: _zoomOut,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.remove, color: Color(0xFF00BFA5)),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton(
                    heroTag: 'zoom_in',
                    mini: true,
                    onPressed: _zoomIn,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.add, color: Color(0xFF00BFA5)),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton.extended(
                    heroTag: 'save_image',
                    onPressed: _savePageAsImage,
                    backgroundColor: const Color(0xFF00BFA5),
                    icon: const Icon(Icons.save_alt, color: Colors.white),
                    label: Text('حفظ كصورة',
                        style: GoogleFonts.cairo(color: Colors.white)),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
