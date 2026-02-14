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
import 'firebase_options.dart';

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

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    required this.timestamp,
    required this.data,
    this.isRead = false,
    this.type = 'general',
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
    );
  }

  factory NotificationItem.fromFirebaseMessage(RemoteMessage message) {
    final imageUrl = message.data['image_url'] ??
        message.notification?.android?.imageUrl ??
        message.notification?.apple?.imageUrl ??
        message.data['image'];

    String title =
        message.notification?.title ?? message.data['title'] ?? 'إشعار جديد';
    String body = message.notification?.body ?? message.data['body'] ?? '';

    return NotificationItem(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      imageUrl: imageUrl,
      timestamp: DateTime.now(),
      data: message.data,
      isRead: false,
      type: message.data['type'] ?? 'general',
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
    );
  }
}

/// =========================
/// NOTIFICATION MANAGER - FIXED
/// =========================

class NotificationManager extends ChangeNotifier {
  static NotificationManager? _instance;
  static NotificationManager get instance =>
      _instance ??= NotificationManager._();

  NotificationManager._();

  List<NotificationItem> _notifications = [];
  int _unreadCount = 0;
  bool _isSyncing = false;
  Timer? _syncTimer;

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;
  bool get isSyncing => _isSyncing;

  // ============================================
  // INITIALIZE - FIXED: Load local first, then sync server
  // ============================================
  Future<void> initialize() async {
    debugPrint('🚀 [Manager] Initializing...');

    // CRITICAL FIX: Load from local storage FIRST (contains notifications saved by background handler)
    await loadNotifications();

    // Then fetch from server to sync and merge any updates
    try {
      await fetchFromMySQL();
      debugPrint('✅ [Manager] Server sync complete after local load');
    } catch (e) {
      debugPrint(
          '⚠️ [Manager] Initial server sync failed, using local data: $e');
    }

    // Start periodic sync to keep updated
    _startPeriodicSync();
  }

  // ============================================
  // FORCE LOAD FROM DISK
  // ============================================
  Future<void> loadNotifications() async {
    try {
      final localList = await NotificationService.getLocalNotifications();

      _notifications =
          localList.map((e) => NotificationItem.fromJson(e)).toList();
      _updateUnreadCount();

      debugPrint('📂 [Manager] Loaded ${_notifications.length} from disk');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [Manager] Load Error: $e');
    }
  }

  // ============================================
  // CRITICAL FIXED: SYNC FROM SERVER
  // Called when app opens, resumes, or periodically
  // iOS FIX: This is now the PRIMARY source of truth
  // ============================================
  Future<void> fetchFromMySQL() async {
    if (_isSyncing) {
      debugPrint('⏳ [Manager] Already syncing, skipping...');
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      debugPrint('🌐 [Manager] Fetching from MySQL...');

      final serverListRaw = await NotificationService
          .getAllNotifications(); // No limit - pull all

      if (serverListRaw.isNotEmpty) {
        final serverItems =
            serverListRaw.map((m) => NotificationItem.fromMySQL(m)).toList();

        // Merge server data with current notifications (preserving local read status)
        _mergeServerWithCurrent(serverItems);

        debugPrint('✅ [Manager] Synced ${serverItems.length} from server');
      } else {
        debugPrint('⚠️ [Manager] No new data from server');
      }
    } catch (e, stacktrace) {
      debugPrint('❌ [Manager] Sync Error: $e');
      debugPrint('❌ [Manager] Stacktrace: $stacktrace');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // ============================================
  // MERGE SERVER NOTIFICATIONS WITH CURRENT LIST
  // ============================================
  void _mergeServerWithCurrent(List<NotificationItem> serverItems) {
    final Map<String, NotificationItem> mergedMap = {};

    // Start with current notifications (from local)
    for (var item in _notifications) {
      mergedMap[item.id] = item;
    }

    // Add/update with server data, preserving read status
    for (var serverItem in serverItems) {
      if (mergedMap.containsKey(serverItem.id)) {
        // Preserve read status from local
        serverItem.isRead = mergedMap[serverItem.id]!.isRead;
      }
      mergedMap[serverItem.id] = serverItem;
    }

    // Convert back to list and sort
    _notifications = mergedMap.values.toList();
    _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Limit to 1000 (adjust as needed)
    if (_notifications.length > 1000) {
      _notifications = _notifications.sublist(0, 1000);
    }

    _updateUnreadCount();

    // Save merged list to disk
    _saveToDisk();
  }

  // ============================================
  // ⚠️ DEPRECATED: Not used in new architecture
  // FCM listeners no longer add to list
  // Notification list is now database-driven only
  // ============================================
  // CRITICAL FIXED: Add Firebase Message
  // Called when notification received while app is open
  // ============================================
  @Deprecated(
      'Use database-driven notifications instead. FCM is for popups only.')
  Future<void> addFirebaseMessage(RemoteMessage message) async {
    final item = NotificationItem.fromFirebaseMessage(message);

    // FIX: Don't ignore any notifications - show them all
    debugPrint('📨 [Manager] Received Firebase message: ${item.id}');
    debugPrint('📨 [Manager] Title: ${item.title}, Body: ${item.body}');

    // Remove if exists (deduplicate)
    _notifications.removeWhere((n) => n.id == item.id);

    // Insert at top
    _notifications.insert(0, item);

    _updateUnreadCount();
    await _saveToDisk();
    notifyListeners();

    debugPrint(
        '✅ [Manager] Added notification, total: ${_notifications.length}, unread: $_unreadCount');
  }

  // ============================================
  // CRITICAL: Add notification from iOS native
  // ============================================
  Future<void> addNotificationFromNative(Map<String, dynamic> data) async {
    try {
      final item = NotificationItem.fromJson(data);

      debugPrint('📱 [Manager] Received iOS notification: ${item.id}');
      debugPrint('📱 [Manager] Title: ${item.title}, Body: ${item.body}');

      // Remove if exists (deduplicate)
      _notifications.removeWhere((n) => n.id == item.id);

      // Insert at top
      _notifications.insert(0, item);

      _updateUnreadCount();
      await _saveToDisk();

      // Save to server
      await NotificationService.saveNotificationToServer(item.toJson());

      notifyListeners();

      debugPrint(
          '✅ [Manager] Added iOS notification, total: ${_notifications.length}');
    } catch (e) {
      debugPrint('❌ [Manager] Error adding iOS notification: $e');
    }
  }

  // ============================================
  // MARK AS READ
  // ============================================
  Future<void> markAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1 && !_notifications[index].isRead) {
      _notifications[index].isRead = true;
      _updateUnreadCount();
      await _saveToDisk();
      notifyListeners();

      // Update in background
      NotificationService.markAsRead(id);
    }
  }

  // ============================================
  // MARK ALL AS READ
  // ============================================
  Future<void> markAllAsRead() async {
    bool changed = false;
    for (var n in _notifications) {
      if (!n.isRead) {
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

  // ============================================
  // DELETE NOTIFICATION
  // ============================================
  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    _updateUnreadCount();
    await _saveToDisk();
    await NotificationService.deleteNotification(id);
    notifyListeners();
  }

  // ============================================
  // CLEAR ALL
  // ============================================
  Future<void> clearAllNotifications() async {
    _notifications.clear();
    _updateUnreadCount();
    await _saveToDisk();
    await NotificationService.clearAllNotifications();
    notifyListeners();
  }

  // ============================================
  // SEARCH
  // ============================================
  List<NotificationItem> searchNotifications(String query) {
    if (query.isEmpty) return _notifications;
    final q = query.toLowerCase();
    return _notifications
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
  }

  // ============================================
  // PRIVATE METHODS
  // ============================================

  void _updateUnreadCount() {
    _unreadCount = _notifications.where((n) => !n.isRead).length;
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr =
          jsonEncode(_notifications.map((e) => e.toJson()).toList());
      await prefs.setString(NotificationService.storageKey, jsonStr);
    } catch (e) {
      debugPrint('❌ [Manager] Save Error: $e');
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      debugPrint('⏰ [Manager] Periodic sync from server');
      fetchFromMySQL();
    });
  }

  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
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
        debugPrint('🔔 Local Notification Tapped');
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

void _navigateToNotifications() {
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // CRITICAL iOS FIX: Initialize notification service
  await NotificationService.initialize();

  debugPrint('🌙 [BG] Message Received: ${message.messageId}');
  debugPrint('🌙 [BG] Title: ${message.notification?.title}');
  debugPrint('🌙 [BG] Body: ${message.notification?.body}');

  final item = NotificationItem.fromFirebaseMessage(message);

  try {
    // CRITICAL iOS FIX: Save to SERVER FIRST with priority
    debugPrint('🌐 [BG] Saving to server with HIGH PRIORITY...');

    // Save to server first (returns bool)
    final serverSaved =
        await NotificationService.saveNotificationToServer(item.toJson());
    debugPrint('✅ [BG] Server save result: $serverSaved');

    // Then save to local disk (returns void)
    await NotificationService.saveToLocalDisk(item.toJson());
    debugPrint('✅ [BG] Local save completed');

    // CRITICAL: Small wait to ensure data is committed
    await Future.delayed(const Duration(milliseconds: 100));

    // Verify the local save
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final verifyStr = prefs.getString(NotificationService.storageKey);
    if (verifyStr != null) {
      final list = jsonDecode(verifyStr);
      final found = list.any((notif) => notif['id'].toString() == item.id);
      debugPrint('✅ [BG] Local save verified: $found');
    }

    debugPrint('✅ [BG] Background processing complete');
  } catch (e) {
    debugPrint('❌ [BG] Error: $e');
  }
}

/// =========================
/// METHOD CHANNEL FOR iOS NOTIFICATIONS
/// =========================
class NotificationMethodChannel {
  static const MethodChannel _channel = MethodChannel('notification_handler');

  static void setupListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'saveNotification') {
        debugPrint('📱 [iOS Channel] Received notification from native iOS');
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(call.arguments);

        // Add to notification manager
        await NotificationManager.instance.addNotificationFromNative(data);
      } else if (call.method == 'navigateToNotifications') {
        debugPrint('📱 [iOS Channel] Navigation command received');
        // Navigate to notifications screen
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const NotificationsScreen()),
          (route) => false,
        );
      }
    });
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// =========================
/// MAIN - FIXED
/// =========================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar_IQ', null);

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    LocalNotificationService.initialize();

    // CRITICAL: Setup iOS method channel
    NotificationMethodChannel.setupListener();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // CRITICAL iOS FIX: Initialize notification manager
    // This will fetch from server first, then fallback to local
    await NotificationManager.instance.initialize();

    final messaging = FirebaseMessaging.instance;

    // Request permissions
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('🔔 Notification permissions: ${settings.authorizationStatus}');

    // Subscribe to topics
    await messaging.subscribeToTopic('all_employees');

    // Get token
    final token = await messaging.getToken();
    debugPrint('🔑 FCM Token: $token');

    if (Platform.isAndroid) {
      await _requestIgnoreBatteryOptimizations();
    }

    await _setupNotificationNavigation(messaging);
  } catch (e) {
    debugPrint('�� Init Error: $e');
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
    // Handle when app is terminated and opened via notification
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🚀 [Launch] App opened from Terminated via Notification');
      // 🔔 FCM = Navigation only
      // 🗂 List = Database driven (fetchFromMySQL)
      Future.delayed(const Duration(seconds: 1), () {
        _navigateToNotifications();
      });
    }
  } catch (e) {
    debugPrint('Error getting initial message: $e');
  }

  // Handle when app is in background and notification is tapped
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    debugPrint('👆 [Click] App opened from Background via Notification');
    // 🔔 FCM = Navigation only
    // 🗂 List = Database driven (fetchFromMySQL)
    _navigateToNotifications();
  });

  // CRITICAL FIXED: Handle when app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('🌞 [FG] Notification received while app is FOREGROUND');
    debugPrint('🌞 [FG] Message ID: ${message.messageId}');
    debugPrint('🌞 [FG] Title: ${message.notification?.title}');
    debugPrint('🌞 [FG] Body: ${message.notification?.body}');

    // 🔔 FCM = Popup notification ONLY
    // 🗂 List = Database driven (fetchFromMySQL)
    // 🚫 DO NOT add to list here

    // Show local notification popup on Android
    if (Platform.isAndroid && message.notification != null) {
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
    NotificationManager.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [Lifecycle] App Resumed - Syncing from server');

      // CRITICAL iOS FIX: Add small delay to allow background handler to complete
      Future.delayed(const Duration(milliseconds: 500), () {
        debugPrint('🔄 [Lifecycle] First fetch attempt');
        NotificationManager.instance.fetchFromMySQL();

        // CRITICAL: Retry after another delay to catch any late saves
        Future.delayed(const Duration(seconds: 2), () {
          debugPrint('🔄 [Lifecycle] Second fetch attempt (retry)');
          NotificationManager.instance.fetchFromMySQL();
        });
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
// UI COMPONENTS (Keep all your existing UI components)
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
                fontSize: 16,
                fontWeight: FontWeight.normal,
                height: 1.6,
                color: const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(height: 32),
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
      }
    } catch (e) {
      // Fall through to fallback
    }

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

class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

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
        child: Center(
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
                Container(
                  width: 140,
                  height: 140,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFA5),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00BFA5).withOpacity(0.3),
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
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFF00BFA5),
                  ),
                ),
              ],
            ),
          ),
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
                      'سيتم الاحتفاظ ببيانات الموظفين طوال فتر�� عملهم في الشركة، وبعد انتهاء الخدمة، سيتم حظها وفقًا للمتطلبات القانونية.',
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

// ============================================
// CRITICAL FIXED: NOTIFICATIONS SCREEN
// ============================================

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all';
  Timer? _refreshTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Load immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _forceRefresh();
    });

    // Start periodic refresh every 3 seconds for real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _forceRefresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [Notifications] App resumed - Force refresh');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _forceRefresh();
        }
      });
    }
  }

  Future<void> _forceRefresh() async {
    debugPrint('🔄 [Notifications Screen] Force refresh started');

    // First load from disk
    await NotificationManager.instance.loadNotifications();

    // Then fetch from server
    await NotificationManager.instance.fetchFromMySQL();

    // CRITICAL iOS FIX: Retry after delay to catch late notifications
    Future.delayed(const Duration(seconds: 2), () async {
      if (mounted) {
        debugPrint(
            '🔄 [Notifications Screen] Retry fetch for late notifications');
        await NotificationManager.instance.fetchFromMySQL();
      }
    });

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
                case 'refresh':
                  await _forceRefresh();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(Icons.refresh, color: Color(0xFF00BFA5)),
                    const SizedBox(width: 8),
                    Text('تحديث', style: GoogleFonts.cairo()),
                  ],
                ),
              ),
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
          if (NotificationManager.instance.isSyncing)
            const LinearProgressIndicator(
              color: Color(0xFF00BFA5),
              minHeight: 2,
            ),
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
                  onRefresh: _forceRefresh,
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
      notifications = notifications
          .where((n) =>
              n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              n.body.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
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
      }
    } catch (e) {
      // Fall through to fallback
    }

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
      } else if (difference.inHours < 24) {
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
      if (mounted) {
        setState(() {
          canGoBack = canNavigateBack;
        });
      }
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
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes, shrink-to-fit=yes, shrink-to-fit=yes';
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
          return originalOpen.call(url, name, specs);
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
        _showMessage('الرجاء منح صلاحية الوصول للصور');
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
      return false;
    }

    bool hasParameter = currentUrl.contains('?') ||
        currentUrl.contains('/view/') ||
        (currentUrl.contains('.html') &&
            currentUrl.split('/').last.length > 15);

    bool isDifferentFromMain = currentUrl.contains('.html') &&
        currentUrl != 'https://gate.scgfs-oil.gov.iq/payslip.html';

    return hasParameter || isDifferentFromMain;
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
