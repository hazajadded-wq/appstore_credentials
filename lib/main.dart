import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:salaryinfo/firebase_options.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';

// SQLite imports
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;

// HTTP import for API calls
import 'package:http/http.dart' as http;

// ========================================
// ✅ Constants
// ========================================
const String API_BASE_URL =
    'https://lpgaspro.org'; // ⚠️ CHANGE THIS TO YOUR SERVER URL
const String API_ENDPOINT = '$API_BASE_URL/notifications_api.php';

// ========================================
// ✅ iOS MethodChannel - FIXED VERSION
// ========================================
const MethodChannel _notificationChannel =
    MethodChannel('com.pocket.salaryinfo/notifications');

/// ✅ Setup iOS MethodChannel handler
Future<void> setupNotificationChannelHandler() async {
  debugPrint('🔧 ========================================');
  debugPrint('🔧 Setting up iOS MethodChannel handler...');
  debugPrint('🔧 Channel name: com.pocket.salaryinfo/notifications');
  debugPrint('🔧 ========================================');

  try {
    _notificationChannel.setMethodCallHandler((MethodCall call) async {
      debugPrint('📲 ========================================');
      debugPrint('📲 📲 📲 MethodChannel RECEIVED CALL 📲 📲 📲');
      debugPrint('📲 ========================================');
      debugPrint('📲 Method: ${call.method}');
      debugPrint('📲 Arguments type: ${call.arguments.runtimeType}');

      if (call.method == 'onNotificationReceived') {
        debugPrint('✅ Method is onNotificationReceived - processing...');

        try {
          final Map<dynamic, dynamic> rawArgs =
              call.arguments as Map<dynamic, dynamic>;
          debugPrint('✅ Arguments cast to Map successfully');

          final String messageId = rawArgs['id']?.toString() ??
              'flutter_${DateTime.now().millisecondsSinceEpoch}';
          final String title = rawArgs['title']?.toString() ?? 'إشعار جديد';
          final String body = rawArgs['body']?.toString() ?? '';
          final int timestamp = rawArgs['timestamp'] is int
              ? rawArgs['timestamp']
              : DateTime.now().millisecondsSinceEpoch;

          debugPrint('✅ Extracted: messageId=$messageId, title=$title');

          final Map<dynamic, dynamic> rawData =
              rawArgs['data'] as Map<dynamic, dynamic>? ?? {};
          final Map<String, dynamic> data = {};
          rawData.forEach((key, value) {
            data[key.toString()] = value;
          });

          debugPrint(
              '✅ Data: type=${data['type']}, image_url=${data['image_url']}');

          final NotificationItem notification = NotificationItem(
            id: messageId,
            title: title,
            body: body,
            imageUrl: data['image_url']?.toString(),
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
            data: data,
            isRead: false,
            type: data['type']?.toString() ?? 'general',
          );

          debugPrint(
              '💾 Adding to NotificationManager... Count before: ${NotificationManager.instance.notifications.length}');

          await NotificationManager.instance.addNotification(notification);

          // ✅ FIX: Force UI update immediately
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NotificationManager.instance.forceUpdate();
          });

          debugPrint(
              '✅✅✅ NOTIFICATION SAVED! Count after: ${NotificationManager.instance.notifications.length}');
          debugPrint('✅ Unread: ${NotificationManager.instance.unreadCount}');
        } catch (e, stackTrace) {
          debugPrint('❌❌❌ ERROR: $e');
          debugPrint('$stackTrace');
        }
      }
    });

    debugPrint('✅ iOS MethodChannel handler setup COMPLETE');
  } catch (e, stackTrace) {
    debugPrint('❌ FAILED to setup MethodChannel: $e');
    debugPrint('$stackTrace');
  }
}

// نموذج بيانات الإشعار
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
      id: json['id'],
      title: json['title'],
      body: json['body'],
      imageUrl: json['imageUrl'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      data: Map<String, dynamic>.from(json['data']),
      isRead: json['isRead'] ?? false,
      type: json['type'] ?? 'general',
    );
  }

  factory NotificationItem.fromFirebaseMessage(RemoteMessage message) {
    String? imageUrl = message.data['image_url'] ??
        message.notification?.android?.imageUrl ??
        message.data['image'];

    return NotificationItem(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: message.notification?.title ?? 'إشعار جديد',
      body: message.notification?.body ?? '',
      imageUrl: imageUrl,
      timestamp: DateTime.now(),
      data: message.data,
      isRead: false,
      type: message.data['type'] ?? 'general',
    );
  }

  // ✅ NEW: Create from MySQL API response
  factory NotificationItem.fromMySQLJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'إشعار جديد',
      body: json['body'] ?? '',
      imageUrl: json['image_url'],
      timestamp:
          DateTime.parse(json['sent_at'] ?? DateTime.now().toIso8601String()),
      data: json['data_payload'] != null
          ? (json['data_payload'] is String
              ? jsonDecode(json['data_payload'])
              : json['data_payload'])
          : {},
      isRead: false,
      type: json['type'] ?? 'general',
    );
  }
}

// NotificationDatabase - SQLite للإشعارات
class NotificationDatabase {
  static final NotificationDatabase instance = NotificationDatabase._init();
  static Database? _database;

  NotificationDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('notifications.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final pathStr = path_package.join(dbPath, filePath);
    debugPrint('📂 Database path: $pathStr');
    return await openDatabase(pathStr, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL,
  imageUrl TEXT,
  timestamp INTEGER NOT NULL,
  isRead INTEGER NOT NULL,
  data TEXT
)
''');
    debugPrint('✅ Database table created');
  }

  Future<void> addNotification(Map<String, dynamic> notification) async {
    final db = await instance.database;
    final existing = await db.query('notifications',
        where: 'id = ?', whereArgs: [notification['id']]);
    if (existing.isNotEmpty) {
      debugPrint('⚠️ Notification already exists: ${notification["id"]}');
      return;
    }
    await db.insert(
        'notifications',
        {
          'id': notification['id'],
          'title': notification['title'],
          'body': notification['body'],
          'type': notification['type'],
          'imageUrl': notification['imageUrl'],
          'timestamp': notification['timestamp'],
          'isRead': notification['isRead'] ? 1 : 0,
          'data': notification['data'] != null
              ? jsonEncode(notification['data'])
              : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint('✅ Notification added to database: ${notification["id"]}');
  }

  Future<List<Map<String, dynamic>>> getAllNotifications() async {
    final db = await instance.database;
    final result = await db.query('notifications', orderBy: 'timestamp DESC');
    debugPrint('📊 Retrieved ${result.length} notifications from database');
    return result
        .map((map) => {
              'id': map['id'],
              'title': map['title'],
              'body': map['body'],
              'type': map['type'],
              'imageUrl': map['imageUrl'],
              'timestamp': map['timestamp'],
              'isRead': map['isRead'] == 1,
              'data': map['data'] != null
                  ? jsonDecode(map['data'] as String)
                  : null,
            })
        .toList();
  }

  Future<void> markAsRead(String id) async {
    final db = await instance.database;
    await db.update('notifications', {'isRead': 1},
        where: 'id = ?', whereArgs: [id]);
    debugPrint('✅ Notification marked as read: $id');
  }

  Future<void> deleteNotification(String id) async {
    final db = await instance.database;
    await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
    debugPrint('🗑️ Notification deleted: $id');
  }

  Future<void> deleteAllNotifications() async {
    final db = await instance.database;
    await db.delete('notifications');
    debugPrint('🗑️ All notifications deleted');
  }
}

// ✅ FIXED: مدير الإشعارات مع StreamController و API Sync
class NotificationManager extends ChangeNotifier {
  static NotificationManager? _instance;
  static NotificationManager get instance =>
      _instance ??= NotificationManager._();

  NotificationManager._();

  List<NotificationItem> _notifications = [];
  int _unreadCount = 0;
  Timer? _syncTimer;
  bool _isSyncing = false;

  // ✅ NEW: StreamController للتحديثات الفورية
  final _updateController = StreamController<void>.broadcast();
  Stream<void> get updateStream => _updateController.stream;

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;

  // ✅ NEW: Start periodic sync with MySQL
  void startPeriodicSync() {
    debugPrint('🔄 Starting periodic sync with MySQL...');

    // Initial sync
    syncWithMySQL();

    // Sync every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncWithMySQL();
    });
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // ✅ NEW: Sync with MySQL database
  Future<void> syncWithMySQL() async {
    if (_isSyncing) {
      debugPrint('⚠️ Sync already in progress, skipping...');
      return;
    }

    _isSyncing = true;
    debugPrint('🔄 Syncing with MySQL database...');

    try {
      final response = await http
          .get(
            Uri.parse('$API_ENDPOINT?action=get_notifications&limit=50'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        if (data['success'] == true) {
          final List<dynamic> serverNotifications = data['notifications'] ?? [];
          debugPrint(
              '📥 Received ${serverNotifications.length} notifications from server');

          int newCount = 0;

          for (var notifData in serverNotifications) {
            try {
              final notification = NotificationItem.fromMySQLJson(notifData);

              // Check if notification already exists
              bool exists = _notifications.any((n) => n.id == notification.id);

              if (!exists) {
                // Add to local database
                await NotificationDatabase.instance.addNotification({
                  'id': notification.id,
                  'title': notification.title,
                  'body': notification.body,
                  'type': notification.type,
                  'imageUrl': notification.imageUrl,
                  'timestamp': notification.timestamp.millisecondsSinceEpoch,
                  'isRead': notification.isRead,
                  'data': notification.data,
                });

                // Add to memory
                _notifications.insert(0, notification);
                newCount++;
              }
            } catch (e) {
              debugPrint('❌ Error parsing notification: $e');
            }
          }

          if (newCount > 0) {
            debugPrint('✅ Added $newCount new notifications from server');
            _updateUnreadCount();
            notifyListeners();
            _updateController.add(null);
          } else {
            debugPrint('ℹ️ No new notifications from server');
          }
        }
      } else {
        debugPrint('❌ Server returned status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error syncing with MySQL: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> loadNotifications() async {
    try {
      debugPrint('📂 Loading notifications from SQLite...');
      final notificationsData =
          await NotificationDatabase.instance.getAllNotifications();
      _notifications = notificationsData.map((data) {
        return NotificationItem(
          id: data['id'] as String,
          title: data['title'] as String,
          body: data['body'] as String,
          imageUrl: data['imageUrl'] as String?,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
          data: data['data'] as Map<String, dynamic>? ?? {},
          isRead: data['isRead'] as bool,
          type: data['type'] as String,
        );
      }).toList();
      _updateUnreadCount();
      debugPrint('✅ Loaded ${_notifications.length} notifications from SQLite');

      // ✅ Now sync with MySQL to get latest
      await syncWithMySQL();
    } catch (e) {
      debugPrint('❌ Error: $e');
    }
  }

  Future<void> addNotification(NotificationItem notification) async {
    if (_notifications.any((n) => n.id == notification.id)) {
      debugPrint('⚠️ Duplicate - skipping');
      return;
    }
    await NotificationDatabase.instance.addNotification({
      'id': notification.id,
      'title': notification.title,
      'body': notification.body,
      'type': notification.type,
      'imageUrl': notification.imageUrl,
      'timestamp': notification.timestamp.millisecondsSinceEpoch,
      'isRead': notification.isRead,
      'data': notification.data,
    });
    _notifications.insert(0, notification);
    if (_notifications.length > 50) {
      _notifications = _notifications.take(50).toList();
    }
    _updateUnreadCount();

    // ✅ FIX: استدعاء الاثنين معاً
    notifyListeners();
    _updateController.add(null);

    debugPrint('✅ Added: ${notification.title}');
  }

  Future<void> addFirebaseMessage(RemoteMessage message) async {
    NotificationItem notification =
        NotificationItem.fromFirebaseMessage(message);
    await addNotification(notification);
  }

  // ✅ NEW: Force update method
  void forceUpdate() {
    notifyListeners();
    _updateController.add(null);
    debugPrint('🔄 Forced UI update');
  }

  Future<void> markAsRead(String notificationId) async {
    int index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1 && !_notifications[index].isRead) {
      await NotificationDatabase.instance.markAsRead(notificationId);
      _notifications[index].isRead = true;
      _updateUnreadCount();
      notifyListeners();
      _updateController.add(null);
      debugPrint('✅ Marked as read: $notificationId');
    }
  }

  Future<void> markAllAsRead() async {
    bool hasChanges = false;
    for (var notification in _notifications) {
      if (!notification.isRead) {
        await NotificationDatabase.instance.markAsRead(notification.id);
        notification.isRead = true;
        hasChanges = true;
      }
    }

    if (hasChanges) {
      _updateUnreadCount();
      notifyListeners();
      _updateController.add(null);
      debugPrint('✅ Marked all as read');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    int initialLength = _notifications.length;
    await NotificationDatabase.instance.deleteNotification(notificationId);
    _notifications.removeWhere((n) => n.id == notificationId);

    if (_notifications.length != initialLength) {
      _updateUnreadCount();
      notifyListeners();
      _updateController.add(null);
      debugPrint('🗑️ Deleted: $notificationId');
    }
  }

  Future<void> clearAllNotifications() async {
    await NotificationDatabase.instance.deleteAllNotifications();
    _notifications.clear();
    _updateUnreadCount();
    notifyListeners();
    _updateController.add(null);
    debugPrint('🗑️ Cleared all');
  }

  void _updateUnreadCount() {
    _unreadCount = _notifications.where((n) => !n.isRead).length;
  }

  List<NotificationItem> getNotificationsByType(String type) {
    return _notifications.where((n) => n.type == type).toList();
  }

  List<NotificationItem> searchNotifications(String query) {
    String lowerQuery = query.toLowerCase();
    return _notifications
        .where((n) =>
            n.title.toLowerCase().contains(lowerQuery) ||
            n.body.toLowerCase().contains(lowerQuery))
        .toList();
  }

  @override
  void dispose() {
    stopPeriodicSync();
    _updateController.close();
    super.dispose();
  }
}

// GlobalKey للتنقل
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _setupNativeFirebaseDelegate() async {
  if (Platform.isIOS) {
    try {
      final messaging = FirebaseMessaging.instance;
      String? token = await messaging.getToken();
      debugPrint(
          "✅ Native Firebase delegate setup complete: ${token?.substring(0, 20)}...");
    } catch (e) {
      debugPrint("❌ Error setting up native Firebase delegate: $e");
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint('📱 Background FCM Message received: ${message.messageId}');
  debugPrint('📱 Message data: ${message.data}');

  await NotificationManager.instance.addFirebaseMessage(message);

  if (message.notification != null) {
    debugPrint('📱 Notification Title: ${message.notification!.title}');
    debugPrint('📱 Notification Body: ${message.notification!.body}');
  }

  debugPrint('✅ Background message processed successfully');
}

Future<void> _handleNotificationTap(RemoteMessage message) async {
  debugPrint('👆 Notification tapped! Message: ${message.messageId}');

  await Future.delayed(const Duration(milliseconds: 500));

  try {
    if (navigatorKey.currentState == null) {
      debugPrint('❌ Navigator not ready yet, waiting...');
      await Future.delayed(const Duration(seconds: 1));
    }

    if (navigatorKey.currentState != null) {
      debugPrint('✅ Navigator ready - pushing NotificationsScreen');
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (context) => const NotificationsScreen(),
        ),
      );
    } else {
      debugPrint('❌ Navigator still not available after waiting');
    }
  } catch (e) {
    debugPrint('❌ Error navigating to NotificationsScreen: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('📂 Initializing SQLite...');
  await NotificationDatabase.instance.database;
  debugPrint('✅ SQLite ready');

  try {
    await initializeDateFormatting('ar_IQ', null);
    debugPrint('✅ Date formatting initialized');
  } catch (e) {
    debugPrint('⚠️ Date formatting failed: $e');
  }

  debugPrint('''
  🚀 =================================
  🚀 Starting SalaryInfo Application
  🚀 Firebase Project: scgfs-salary-app
  🚀 Bundle ID: com.pocket.salaryinfo
  🚀 Platform: ${Platform.operatingSystem}
  🚀 =================================
  ''');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await configureFirebaseMessaging();

    if (Platform.isIOS) {
      debugPrint('📱 Platform is iOS - setting up MethodChannel...');
      await setupNotificationChannelHandler();
      debugPrint('✅ iOS MethodChannel handler initialized');
    }

    debugPrint('✅ Firebase initialized successfully');

    final app = Firebase.app();
    debugPrint('✅ Firebase App Name: ${app.name}');
    debugPrint('✅ Firebase Project ID: ${app.options.projectId}');

    await _setupNativeFirebaseDelegate();
    await NotificationManager.instance.loadNotifications();

    // ✅ Start periodic sync with MySQL
    NotificationManager.instance.startPeriodicSync();

    debugPrint('✅ Notification Manager initialized');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('✅ Background message handler registered');
  } catch (e) {
    debugPrint('⚠️ Firebase init error: $e');
    debugPrint('⚠️ Continuing without Firebase features');
  }

  try {
    await GoogleFonts.pendingFonts([GoogleFonts.cairo()]);
    debugPrint('✅ Google Fonts loaded');
  } catch (e) {
    debugPrint('⚠️ Google Fonts loading failed: $e');
  }

  debugPrint('✅ All initializations complete - Running app');
  runApp(const MyApp());
}

Future<void> configureFirebaseMessaging() async {
  if (Platform.isIOS) {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  try {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
        '🔔 Notification permission status: ${settings.authorizationStatus}');

    String? token = await messaging.getToken().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('⚠️ FCM token request timeout');
        return null;
      },
    );

    if (token != null) {
      debugPrint('🔑 FCM Token: ${token.substring(0, 20)}...');

      await messaging.subscribeToTopic('all_employees').timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Topic subscription timeout');
        },
      );
      debugPrint('📧 Subscribed to topic: all_employees');
    } else {
      debugPrint('⚠️ No FCM token received');
    }

    // ✅ FIX: iOS now uses BOTH native AppDelegate AND Dart handlers
    if (Platform.isAndroid) {
      debugPrint('🤖 Setting up Android Firebase handlers');

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📱 [Android] Foreground FCM Message: ${message.messageId}');
        NotificationManager.instance.addFirebaseMessage(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('👆 [Android] Notification tapped: ${message.messageId}');
        NotificationManager.instance.addFirebaseMessage(message);
        _handleNotificationTap(message);
      });

      RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('📱 [Android] App launched from notification');
        NotificationManager.instance.addFirebaseMessage(initialMessage);
        Future.delayed(const Duration(seconds: 1), () {
          _handleNotificationTap(initialMessage);
        });
      }
    } else {
      debugPrint('🍎 iOS detected - Using native AppDelegate + MethodChannel');

      // ✅ FIX: iOS ALSO listens to onMessage for foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📱 [iOS] Foreground FCM Message: ${message.messageId}');
        debugPrint('   (Will be handled by AppDelegate + MethodChannel)');
        // ✅ Still add to manager in case MethodChannel fails
        NotificationManager.instance.addFirebaseMessage(message);
      });

      // ✅ Handle initial message for iOS
      RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('📱 [iOS] App launched from notification');
        NotificationManager.instance.addFirebaseMessage(initialMessage);
        Future.delayed(const Duration(milliseconds: 1500), () {
          _handleNotificationTap(initialMessage);
        });
      }
    }

    debugPrint('✅ Firebase Messaging configured successfully');
  } catch (e, stackTrace) {
    debugPrint('❌ Firebase Messaging configuration error: $e');
    debugPrint('❌ Stack trace: $stackTrace');
    debugPrint('⚠️ Push notifications may not work');
  }
}

// ... (Rest of the UI code remains the same - ModernCard, ModernButton, etc.)
// ... (I'll include the full NotificationsScreen with StreamBuilder)

// [CONTINUES WITH REST OF YOUR EXISTING UI CODE - TOO LONG TO SHOW ALL]

final ThemeData appTheme = ThemeData(
  primarySwatch: Colors.teal,
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF00BFA5),
    brightness: Brightness.light,
  ),
  textTheme: TextTheme(
    displayLarge: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    displayMedium: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    displaySmall: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.cairo(fontWeight: FontWeight.w600),
    headlineSmall: GoogleFonts.cairo(fontWeight: FontWeight.w600),
    titleLarge: GoogleFonts.cairo(fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.cairo(fontWeight: FontWeight.w500),
    titleSmall: GoogleFonts.cairo(fontWeight: FontWeight.w500),
    bodyLarge: GoogleFonts.cairo(),
    bodyMedium: GoogleFonts.cairo(),
    bodySmall: GoogleFonts.cairo(),
    labelLarge: GoogleFonts.cairo(fontWeight: FontWeight.w500),
    labelMedium: GoogleFonts.cairo(),
    labelSmall: GoogleFonts.cairo(),
  ),
  appBarTheme: AppBarTheme(
    centerTitle: true,
    backgroundColor: const Color(0xFF00BFA5),
    foregroundColor: Colors.white,
    elevation: 0,
    titleTextStyle: GoogleFonts.cairo(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

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
    return ChangeNotifierBuilder<NotificationManager>(
      notifier: NotificationManager.instance,
      builder: (context, notificationManager, child) {
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
            if (notificationManager.unreadCount > 0)
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
                    notificationManager.unreadCount > 99
                        ? '99+'
                        : notificationManager.unreadCount.toString(),
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

class ChangeNotifierBuilder<T extends ChangeNotifier> extends StatelessWidget {
  final T notifier;
  final Widget Function(BuildContext context, T notifier, Widget? child)
      builder;
  final Widget? child;

  const ChangeNotifierBuilder({
    Key? key,
    required this.notifier,
    required this.builder,
    this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: notifier,
      builder: (context, child) => builder(context, notifier, child),
      child: child,
    );
  }
}

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
                height: 1.6,
                color: const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(height: 32),
            if (notification.data.isNotEmpty && notification.data.length > 1)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'معلومات إضافية',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D3748),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...notification.data.entries
                      .where((entry) =>
                          entry.key != 'image_url' &&
                          entry.key != 'type' &&
                          entry.key != 'timestamp')
                      .map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key}: ',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4A5568),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.value.toString(),
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                color: const Color(0xFF718096),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
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
              child: Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFF00BFA5),
                ),
              ),
            ),
            errorWidget: (context, url, error) {
              return Container(
                color: Colors.grey[100],
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.grey[400],
                        size: 50,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'تعذر تحميل الصورة',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              color: Colors.grey[400],
              size: 50,
            ),
            const SizedBox(height: 8),
            Text(
              'رابط الصورة غير صالح',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
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
  bool _hasError = false;

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
        try {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const PrivacyPolicyScreen(),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 600),
            ),
          );
        } catch (e) {
          setState(() {
            _hasError = true;
          });
        }
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
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 20),
              const Text('خطأ في التحميل', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const WebViewScreen(),
                    ),
                  );
                },
                child: const Text('المتابعة'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFE8F5F3),
              const Color(0xFFD4EDE9),
              const Color(0xFFC0E5DF),
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
            Positioned(
              bottom: -150,
              left: -100,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: 400,
                  height: 400,
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
                                return Icon(
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
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF00BFA5),
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
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00BFA5),
                  const Color(0xFF00A896),
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
                Icon(
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
                const SizedBox(height: 8),
                Text(
                  'يرجى قراءة سياسة الخصوصية بعناية',
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.9),
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
                      'تتخذ الشركة العامة لتعبئة وخدمات الغاز جميع التدابير الأمنية اللازمة لحماية بيانات الموظفين من الوصول غير المصرح به أو الكشف عنها.',
                    ),
                    _buildPrivacySection(
                      '5. مشاركة البيانات',
                      'لن يتم مشاركة بيانات الموظفين مع أي جهة خارجية إلا في حالات ضرورية مثل الامتثال للقوانين أو بموافقة الموظف.',
                    ),
                    _buildPrivacySection(
                      '6. الاحتفاظ بالبيانات',
                      'سيتم الاحتفاظ ببيانات الموظفين طوال فترة عملهم في الشركة، وبعد انتهاء الخدمة، سيتم حفظها وفقًا للمتطلبات القانونية.',
                    ),
                    _buildPrivacySection(
                      '7. حقوق الموظف',
                      'يحق للموظف الاطلاع على بياناته، وطلب تصحيح أي خطأ، أو حذف بياناته بعد انتهاء العلاقة الوظيفية، ما لم يكن الاحتفاظ بها مطلوبًا قانونيًا.',
                    ),
                    _buildPrivacySection(
                      '8. التعديلات على السياسة',
                      'قد تقوم الشركة العامة لتعبئة وخدمات الغاز بتحديث هذه السياسة من وقت لآخر، وسيتم إخطار الموظفين بأي تعديل من خلال التطبيق.',
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

// ✅ FIXED: صفحة الإشعارات مع StreamSubscription
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all';

  // ✅ NEW: StreamSubscription للاستماع للتحديثات
  StreamSubscription<void>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _registerFCMToken();

    // ✅ FIX: الاستماع للتحديثات من NotificationManager
    _listenToNotificationUpdates();
  }

  // ✅ NEW: Listen to notification updates
  void _listenToNotificationUpdates() {
    _notificationSubscription =
        NotificationManager.instance.updateStream.listen((_) {
      debugPrint('🔔 Notification update received - refreshing UI');
      if (mounted) {
        setState(() {});
      }
    });
    debugPrint('✅ Listening to notification updates');
  }

  Future<void> _registerFCMToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      String? token = await messaging.getToken();
      if (token != null) {
        debugPrint('🔑 Current FCM Token: $token');
      }
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          'الإشعارات',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تم تحديد جميع الإشعارات كمقروءة',
                          style: GoogleFonts.cairo(),
                        ),
                        backgroundColor: const Color(0xFF00BFA5),
                      ),
                    );
                  }
                  break;
                case 'clear_all':
                  bool? confirm = await _showDeleteConfirmDialog();
                  if (confirm == true) {
                    await NotificationManager.instance.clearAllNotifications();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تم حذف جميع الإشعارات',
                            style: GoogleFonts.cairo(),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
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
          Expanded(
            child: ChangeNotifierBuilder<NotificationManager>(
              notifier: NotificationManager.instance,
              builder: (context, notificationManager, child) {
                List<NotificationItem> filteredNotifications =
                    _getFilteredNotifications(notificationManager);

                debugPrint(
                    '📊 Displaying ${filteredNotifications.length} notifications');

                if (filteredNotifications.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await NotificationManager.instance.loadNotifications();
                    setState(() {});
                  },
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

  List<NotificationItem> _getFilteredNotifications(
      NotificationManager manager) {
    List<NotificationItem> notifications = manager.notifications;

    if (_selectedFilter != 'all') {
      notifications =
          notifications.where((n) => n.type == _selectedFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      notifications = manager.searchNotifications(_searchQuery);
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم حذف الإشعار',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
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

            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NotificationDetailScreen(
                    notification: notification,
                  ),
                ),
              );
            }
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

  Future<bool?> _showDeleteConfirmDialog({bool single = false}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
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

  final String loginUrl = 'http://109.224.38.44:5000/login';
  WebViewController? controller;
  bool isLoading = true;
  double loadingProgress = 0.0;
  bool canGoBack = false;
  bool hasError = false;
  String errorMessage = '';
  String currentUrl = '';
  bool isLoggedIn = false;
  String lastNavigatedUrl = '';
  int navigationCount = 0;
  double zoomLevel = 1.0;

  final GlobalKey _webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeWebView();
      }
    });
  }

  void _initializeWebView() {
    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white);

      if (Platform.isAndroid) {
        final androidController =
            controller!.platform as AndroidWebViewController;
        androidController.setMediaPlaybackRequiresUserGesture(false);
        controller!.enableZoom(true);
      } else if (Platform.isIOS) {
        final wkWebViewController =
            controller!.platform as WebKitWebViewController;
        wkWebViewController.setAllowsBackForwardNavigationGestures(true);
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
          },
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                loadingProgress = progress / 100;
              });
            }
          },
          onPageFinished: (String url) {
            navigationCount = 0;

            if (mounted) {
              setState(() {
                isLoading = false;
                loadingProgress = 1.0;
                currentUrl = url;
                isLoggedIn = !url.contains('/login');
              });
            }
            _updateCanGoBack();

            if (url.contains('/payslips/view') || url.contains('/salary')) {
              setState(() {
                zoomLevel = 1.0;
              });
            }

            if (Platform.isAndroid) {
              _injectAndroidFix();
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                isLoading = false;
                hasError = true;
                errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url == lastNavigatedUrl) {
              navigationCount++;

              if (navigationCount > 2) {
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
      if (Platform.isIOS) {
        await controller!.runJavaScript('''
          (function() {
            var body = document.body;
            body.style.transform = 'scale($zoomLevel)';
            body.style.transformOrigin = 'top right';
            body.style.width = (100 / $zoomLevel) + '%';
          })();
        ''');
      } else {
        await controller!.runJavaScript('''
          (function() {
            var html = document.documentElement;
            html.style.transform = 'scale($zoomLevel)';
            html.style.width = (100 / $zoomLevel) + '%';
          })();
        ''');
      }
    } catch (e) {
      debugPrint('❌ Error applying zoom: $e');
    }
  }

  Future<void> _injectAndroidFix() async {
    if (controller == null) return;

    const String jsCode = '''
      (function() {
        var originalOpen = window.open;
        window.open = function(url, name, specs) {
          if (url) {
            var cleanUrl = url.replace(/[?&]download=1/, '');
            if (cleanUrl !== window.location.href) {
              window.location.href = cleanUrl;
            }
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
        if (status.isGranted) {
          return true;
        }

        final result = await Permission.storage.request();
        return result.isGranted;
      } catch (e) {
        return true;
      }
    }

    return true;
  }

  Future<Uint8List> _captureWebView() async {
    if (Platform.isIOS) {
      try {
        final dynamic bytes = await _channel.invokeMethod('takeSnapshot');
        if (bytes == null) {
          throw Exception('iOS native method returned null');
        }
        final Uint8List imageBytes = Uint8List.fromList(List<int>.from(bytes));
        return imageBytes;
      } catch (e) {
        throw Exception('iOS screenshot failed: $e');
      }
    } else {
      try {
        if (_webViewKey.currentContext == null) {
          throw Exception('WebView context is null');
        }

        RenderRepaintBoundary? boundary = _webViewKey.currentContext!
            .findRenderObject() as RenderRepaintBoundary?;

        if (boundary == null) {
          throw Exception('RenderRepaintBoundary not found');
        }

        ui.Image img = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData =
            await img.toByteData(format: ui.ImageByteFormat.png);

        if (byteData == null) {
          throw Exception('Failed to convert image to ByteData');
        }

        return byteData.buffer.asUint8List();
      } catch (e) {
        throw Exception('Android screenshot failed: $e');
      }
    }
  }

  Future<void> _savePageAsImage() async {
    try {
      bool hasPermission = await _requestPermissions();
      if (!hasPermission) {
        _showMessage('الرجاء منح صلاحية الوصول للصور لحفظ لقطة الشاشة');
        return;
      }

      if (mounted) {
        setState(() {
          isLoading = true;
        });
      }

      await Future.delayed(const Duration(milliseconds: 1000));

      Uint8List screenshot = await _captureWebView();

      if (screenshot.isEmpty) {
        _showMessage('فشل التقاط الصورة - الرجاء المحاولة مرة أخرى');
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'salary_slip_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(screenshot);

      try {
        await Gal.putImage(tempFile.path, album: 'قسائم الرواتب');

        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }

        _showMessage('تم حفظ قسيمة الراتب في المعرض');

        await Future.delayed(const Duration(seconds: 1), () async {
          try {
            await tempFile.delete();
          } catch (e) {
            debugPrint('⚠️ Error deleting temp file: $e');
          }
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        _showMessage('فشل حفظ الصورة في المعرض');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
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
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.exit_to_app,
                  color: const Color(0xFF00BFA5),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'الخروج من التطبيق',
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D3748),
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'هل تريد الخروج من التطبيق؟',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: const Color(0xFF4A5568),
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  'لا',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              ElevatedButton(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'نعم',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
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
                if (shouldExit == true) {
                  SystemNavigator.pop();
                }
              }
            },
          ),
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              'الشركة العامة لتعبئة وخدمات الغاز',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ),
          actions: [
            NotificationIcon(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
              color: Colors.white,
              child: Center(
                child: controller == null && !hasError
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFF00BFA5),
                              ),
                              strokeWidth: 4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'جاري تحميل التطبيق...',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              color: const Color(0xFF2D3748),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ),
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
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.error_outline,
                          size: 60,
                          color: Colors.red.shade400,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        'يرجى الاتصال بالانترنيت',
                        style: GoogleFonts.cairo(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2D3748),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 15),
                      Text(
                        errorMessage,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      ModernButton(
                        onPressed: () {
                          setState(() {
                            hasError = false;
                          });
                          _initializeWebView();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'إعادة المحاولة',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isLoading && !hasError)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: ModernCard(
                    width: 220,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: loadingProgress > 0 ? loadingProgress : null,
                            minHeight: 8,
                            backgroundColor: Colors.grey.withOpacity(0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF00BFA5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          loadingProgress > 0
                              ? 'جاري التحميل... ${(loadingProgress * 100).toInt()}%'
                              : 'جاري التحميل...',
                          style: GoogleFonts.cairo(
                            color: const Color(0xFF2D3748),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: Platform.isIOS
            ? (currentUrl.contains('/payslips/view') && !hasError
                ? FloatingActionButton.extended(
                    heroTag: 'save_image',
                    onPressed: _savePageAsImage,
                    backgroundColor: const Color(0xFF00BFA5),
                    icon: const Icon(Icons.save_alt, color: Colors.white),
                    label: Text(
                      'حفظ كصورة',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    elevation: 6,
                  )
                : null)
            : (currentUrl.contains('/payslips/view') && !hasError
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FloatingActionButton(
                        heroTag: 'zoom_out',
                        mini: true,
                        onPressed: _zoomOut,
                        backgroundColor: Colors.white,
                        elevation: 4,
                        child: const Icon(Icons.zoom_out,
                            color: Color(0xFF00BFA5), size: 20),
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton(
                        heroTag: 'zoom_in',
                        mini: true,
                        onPressed: _zoomIn,
                        backgroundColor: Colors.white,
                        elevation: 4,
                        child: const Icon(Icons.zoom_in,
                            color: Color(0xFF00BFA5), size: 20),
                      ),
                      const SizedBox(width: 16),
                      FloatingActionButton.extended(
                        heroTag: 'save_image',
                        onPressed: _savePageAsImage,
                        backgroundColor: const Color(0xFF00BFA5),
                        icon: const Icon(Icons.save_alt, color: Colors.white),
                        label: Text(
                          'حفظ كصورة',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        elevation: 6,
                      ),
                    ],
                  )
                : null),
      ),
    );
  }
}
