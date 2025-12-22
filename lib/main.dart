import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:salaryinfo/firebase_options.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
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

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
}

// مدير الإشعارات
class NotificationManager extends ChangeNotifier {
  static NotificationManager? _instance;
  static NotificationManager get instance =>
      _instance ??= NotificationManager._();

  NotificationManager._();

  List<NotificationItem> _notifications = [];
  int _unreadCount = 0;

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;

  Future<void> loadNotifications() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? notificationsJson = prefs.getString('stored_notifications');

      if (notificationsJson != null) {
        List<dynamic> notificationsList = json.decode(notificationsJson);
        _notifications = notificationsList
            .map((json) => NotificationItem.fromJson(json))
            .toList();
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _updateUnreadCount();
        notifyListeners();
        debugPrint('📱 Loaded ${_notifications.length} notifications');
      }
    } catch (e) {
      debugPrint('❌ Error loading notifications: $e');
    }
  }

  Future<void> saveNotifications() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String notificationsJson = json.encode(
          _notifications.map((notification) => notification.toJson()).toList());
      await prefs.setString('stored_notifications', notificationsJson);
      debugPrint('💾 Saved ${_notifications.length} notifications');
    } catch (e) {
      debugPrint('❌ Error saving notifications: $e');
    }
  }

  Future<void> addNotification(NotificationItem notification) async {
    try {
      // 🔥 CRITICAL: منع الإشعارات المكررة
      bool exists = _notifications.any((n) => n.id == notification.id);
      if (exists) {
        debugPrint('⚠️ Notification already exists: ${notification.id}');
        return;
      }

      _notifications.insert(0, notification);
      if (_notifications.length > 100) {
        _notifications = _notifications.take(100).toList();
      }

      _updateUnreadCount();
      await saveNotifications();
      notifyListeners();

      debugPrint('✅ Added notification: ${notification.title}');
      debugPrint('✅ Total: ${_notifications.length}, Unread: $_unreadCount');
    } catch (e) {
      debugPrint('❌ Error adding notification: $e');
    }
  }

  Future<void> addFirebaseMessage(RemoteMessage message) async {
    try {
      NotificationItem notification =
          NotificationItem.fromFirebaseMessage(message);
      await addNotification(notification);
    } catch (e) {
      debugPrint('❌ Error adding Firebase message: $e');
    }
  }

  Future<void> markAsRead(String notificationId) async {
    int index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1 && !_notifications[index].isRead) {
      _notifications[index].isRead = true;
      _updateUnreadCount();
      await saveNotifications();
      notifyListeners();
      debugPrint('✅ Marked notification as read: $notificationId');
    }
  }

  Future<void> markAllAsRead() async {
    bool hasChanges = false;
    for (var notification in _notifications) {
      if (!notification.isRead) {
        notification.isRead = true;
        hasChanges = true;
      }
    }

    if (hasChanges) {
      _updateUnreadCount();
      await saveNotifications();
      notifyListeners();
      debugPrint('✅ Marked all notifications as read');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    int initialLength = _notifications.length;
    _notifications.removeWhere((n) => n.id == notificationId);

    if (_notifications.length != initialLength) {
      _updateUnreadCount();
      await saveNotifications();
      notifyListeners();
      debugPrint('🗑️ Deleted notification: $notificationId');
    }
  }

  Future<void> clearAllNotifications() async {
    _notifications.clear();
    _updateUnreadCount();
    await saveNotifications();
    notifyListeners();
    debugPrint('🗑️ Cleared all notifications');
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

  // 🔥 NEW: Force refresh
  void forceRefresh() {
    _updateUnreadCount();
    notifyListeners();
    debugPrint('🔄 Force refreshed notifications');
  }
}

// GlobalKey للتنقل
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ✅ Background message handler for Firebase Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint('📱 Background FCM Message received: ${message.messageId}');
  debugPrint('📱 Title: ${message.notification?.title}');

  // 🔥 CRITICAL: حفظ الإشعار في الخلفية
  await NotificationManager.instance.addFirebaseMessage(message);

  debugPrint('✅ Background message saved');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initializeDateFormatting('ar_IQ', null);
    debugPrint('✅ Date formatting initialized');
  } catch (e) {
    debugPrint('⚠️ Date formatting failed: $e');
  }

  debugPrint('''
  🚀 =================================
  🚀 Starting SalaryInfo Application
  🚀 Platform: ${Platform.operatingSystem}
  🚀 =================================
  ''');

  try {
    // 🔥 CRITICAL: تهيئة Firebase أولاً
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    debugPrint('✅ Firebase initialized successfully');

    // 🔥 CRITICAL: تهيئة NotificationManager ثانياً
    await NotificationManager.instance.loadNotifications();
    debugPrint('✅ Notification Manager initialized');

    // 🔥 CRITICAL: تكوين FirebaseMessaging ثالثاً
    await configureFirebaseMessaging();

    debugPrint('✅ Firebase Messaging configured');
  } catch (e) {
    debugPrint('⚠️ Firebase init error: $e');
  }

  try {
    await GoogleFonts.pendingFonts([GoogleFonts.cairo()]);
    debugPrint('✅ Google Fonts loaded');
  } catch (e) {
    debugPrint('⚠️ Google Fonts loading failed: $e');
  }

  debugPrint('✅ All initializations complete');

  runApp(const MyApp());
}

// 🔥 CRITICAL FIX: دالة تكوين FirebaseMessaging المحسنة
Future<void> configureFirebaseMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;

    // 🔥 CRITICAL: Request permissions
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('🔔 Permission status: ${settings.authorizationStatus}');

    // 🔥 CRITICAL: iOS foreground settings
    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('🍎 iOS foreground settings configured');
    }

    // 🔥 CRITICAL: Get FCM token
    String? token = await messaging.getToken();
    if (token != null) {
      debugPrint('🔑 FCM Token: ${token.substring(0, 20)}...');

      await messaging.subscribeToTopic('all_employees');
      debugPrint('📧 Subscribed to topic: all_employees');
    }

    // 🔥 CRITICAL FIX 1: Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('📱 FOREGROUND Notification received');
      debugPrint('📱 Title: ${message.notification?.title}');
      debugPrint('📱 Body: ${message.notification?.body}');
      debugPrint('📱 Data: ${message.data}');
      debugPrint('📱 Message ID: ${message.messageId}');

      // 🔥 Add to notification manager
      await NotificationManager.instance.addFirebaseMessage(message);

      // 🔥 Force update UI
      NotificationManager.instance.forceRefresh();
    });

    // 🔥 CRITICAL FIX 2: Handle notification tap (when app is in background or terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      debugPrint('👆 NOTIFICATION TAPPED - App was in BACKGROUND/TERMINATED');
      debugPrint('📱 Title: ${message.notification?.title}');
      debugPrint('📱 Message ID: ${message.messageId}');

      // 🔥 Add notification
      await NotificationManager.instance.addFirebaseMessage(message);

      // 🔥 Force update UI
      NotificationManager.instance.forceRefresh();

      // 🔥 Navigate to notifications screen
      _navigateToNotificationsScreen();
    });

    // 🔥 CRITICAL FIX 3: Handle initial notification (app opened from terminated state)
    RemoteMessage? initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('📱 APP OPENED FROM NOTIFICATION (Terminated state)');
      debugPrint('📱 Title: ${initialMessage.notification?.title}');

      await NotificationManager.instance.addFirebaseMessage(initialMessage);
      NotificationManager.instance.forceRefresh();

      // 🔥 Navigate after delay to ensure app is ready
      Future.delayed(const Duration(seconds: 1), () {
        _navigateToNotificationsScreen();
      });
    }

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    debugPrint('✅ Firebase Messaging fully configured');
  } catch (e, stackTrace) {
    debugPrint('❌ Firebase Messaging configuration error: $e');
    debugPrint('❌ Stack trace: $stackTrace');
  }
}

// 🔥 Helper function: Navigate to notifications screen
void _navigateToNotificationsScreen() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      if (navigatorKey.currentState != null) {
        // 🔥 Clear all existing routes and go to notifications
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const NotificationsScreen()),
          (route) => false,
        );
        debugPrint('✅ Navigated to NotificationsScreen');
      } else {
        debugPrint('❌ NavigatorKey not ready, storing intent...');
        // يمكنك حفظ النية للتنقل لاحقاً
      }
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
    }
  });
}

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

// أيقونة الإشعارات مع Badge صغير
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

// صفحة تفاصيل الإشعار
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
            if (notification.data.isNotEmpty && notification.data.length > 1)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الشركة العامة لتعبئة وخدمات الغاز',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
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
    debugPrint('🚀 SplashScreen initState');

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
      debugPrint('⏰ Timer completed - Navigating to Privacy Policy');
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
          debugPrint('❌ Navigation error: $e');
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
    debugPrint('🔒 PrivacyPolicyScreen rendered');

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
                debugPrint('✅ Privacy Policy accepted - Navigating to WebView');
                try {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const WebViewScreen(),
                    ),
                  );
                } catch (e) {
                  debugPrint('❌ Navigation error: $e');
                  try {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const WebViewScreen(),
                      ),
                    );
                  } catch (e2) {
                    debugPrint('❌ Emergency navigation also failed: $e2');
                  }
                }
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

// صفحة الإشعارات
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('📱 NotificationsScreen opened');

    // 🔥 Force refresh when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationManager.instance.forceRefresh();
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
    debugPrint('📱 AppLifecycleState changed: $state');

    // 🔥 Refresh when app returns to foreground
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed, refreshing notifications...');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationManager.instance.forceRefresh();
      });
    }
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'تم تحديد جميع الإشعارات كمقروءة',
                        style: GoogleFonts.cairo(),
                      ),
                      backgroundColor: const Color(0xFF00BFA5),
                    ),
                  );
                  break;
                case 'clear_all':
                  bool? confirm = await _showDeleteConfirmDialog();
                  if (confirm == true) {
                    await NotificationManager.instance.clearAllNotifications();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حذف الإشعار',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
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
            child: Center(
              child: CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00BFA5)),
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

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);

    debugPrint('🌐 WebViewScreen initState');
    debugPrint('🔗 Login URL: $loginUrl');

    // 🔥 Setup notification handler
    _setupNotificationHandler();

    // Initialize WebView
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        debugPrint('🚀 Starting WebView initialization...');
        _initializeWebView();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🌐 WebView lifecycle: $state');

    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 WebView resumed, refreshing notifications');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationManager.instance.loadNotifications();
      });
    }
  }

  void _setupNotificationHandler() {
    // 🔥 Handle notification tap when app is already open
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      debugPrint('👆 NOTIFICATION TAPPED - App is OPEN');
      debugPrint('📱 Title: ${message.notification?.title}');

      // Add notification
      await NotificationManager.instance.addFirebaseMessage(message);

      // Navigate to notifications
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
            debugPrint('✅ Navigated to NotificationsScreen from WebView');
          } catch (e) {
            debugPrint('❌ Navigation error in WebView: $e');
          }
        });
      }
    });
  }

  void _initializeWebView() {
    debugPrint('⚙️ Initializing WebView...');

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
        debugPrint('🤖 Configuring Android WebView settings');
        final androidController =
            controller!.platform as AndroidWebViewController;
        androidController.setMediaPlaybackRequiresUserGesture(false);
        controller!.enableZoom(true);
        debugPrint('✅ Android WebView settings configured');
      } else if (Platform.isIOS) {
        debugPrint('🍎 Configuring iOS WebView settings');
        final wkWebViewController =
            controller!.platform as WebKitWebViewController;
        wkWebViewController.setAllowsBackForwardNavigationGestures(true);
        debugPrint('✅ iOS WebView settings configured');
      }

      controller!.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('📄 Page started: $url');

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
            debugPrint('⏳ Progress: $progress%');
            if (mounted) {
              setState(() {
                loadingProgress = progress / 100;
              });
            }
          },
          onPageFinished: (String url) {
            debugPrint('✅ Page finished: $url');

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

            if (url.contains('/login')) {
              debugPrint('🔐 Login page detected - hiding notifications');
              _hideNotificationsOnLoginPage();
            }

            if (url.contains('/payslips/view') || url.contains('/salary')) {
              debugPrint('📄 Payslip page detected - auto-fitting to screen');
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
            debugPrint('❌ WebView Error:');
            debugPrint('   Description: ${error.description}');
            debugPrint('   Error code: ${error.errorCode}');
            debugPrint('   Error type: ${error.errorType}');

            if (mounted) {
              setState(() {
                isLoading = false;
                hasError = true;
                errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('🔗 Navigation request: ${request.url}');

            if (request.url == lastNavigatedUrl) {
              navigationCount++;
              debugPrint(
                  '⚠️ Duplicate navigation detected. Count: $navigationCount');

              if (navigationCount > 2) {
                debugPrint('🛑 Blocking repeated navigation to prevent loop');
                return NavigationDecision.prevent;
              }
            } else {
              lastNavigatedUrl = request.url;
              navigationCount = 1;
            }

            if (request.url.contains('/login') ||
                request.url.contains('/dashboard') ||
                request.url.contains('/salary') ||
                request.url.contains('/payslips') ||
                request.url.contains('109.224.38.44')) {
              return NavigationDecision.navigate;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

      debugPrint('🚀 Loading URL: $loginUrl');
      controller!.loadRequest(Uri.parse(loginUrl));

      if (mounted) {
        setState(() {});
      }

      debugPrint('✅ WebView initialized successfully');
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

    debugPrint('📐 Auto-fitting page to screen...');

    try {
      await controller!.runJavaScript('''
        (function() {
          console.log('Auto-fit page script loading...');
          
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
          
          var containers = document.querySelectorAll('div.container, div.content, main, article');
          containers.forEach(function(container) {
            container.style.maxWidth = '100%';
            container.style.width = '100%';
            container.style.padding = '8px';
            container.style.boxSizing = 'border-box';
          });
          
          var tables = document.querySelectorAll('table');
          tables.forEach(function(table) {
            table.style.width = '100%';
            table.style.maxWidth = '100%';
            table.style.fontSize = '14px';
            table.style.display = 'block';
            table.style.overflowX = 'auto';
          });
          
          console.log('✅ Page auto-fitted to screen');
        })();
      ''');

      debugPrint('✅ Auto-fit completed');
    } catch (e) {
      debugPrint('⚠️ Error auto-fitting page: $e');
    }
  }

  void _zoomIn() {
    debugPrint('➕ Zoom In pressed, current zoom: $zoomLevel');
    if (zoomLevel < 3.0) {
      setState(() {
        zoomLevel += 0.2;
        debugPrint('🔄 New zoom level: $zoomLevel');
      });
      _applyZoom();
    } else {
      debugPrint('⛔ Max zoom reached');
    }
  }

  void _zoomOut() {
    debugPrint('➖ Zoom Out pressed, current zoom: $zoomLevel');
    if (zoomLevel > 0.5) {
      setState(() {
        zoomLevel -= 0.2;
        debugPrint('🔄 New zoom level: $zoomLevel');
      });
      _applyZoom();
    } else {
      debugPrint('⛔ Min zoom reached');
    }
  }

  Future<void> _applyZoom() async {
    if (controller == null) {
      debugPrint('⛔ Controller is null, cannot apply zoom');
      return;
    }

    debugPrint('🎯 Applying zoom: $zoomLevel');

    try {
      if (Platform.isIOS) {
        await controller!.runJavaScript('''
          (function() {
            var body = document.body;
            var html = document.documentElement;
            
            body.style.transform = '';
            body.style.webkitTransform = '';
            html.style.transform = '';
            html.style.webkitTransform = '';
            
            body.style.transform = 'scale(' + $zoomLevel + ')';
            body.style.webkitTransform = 'scale(' + $zoomLevel + ')';
            body.style.transformOrigin = 'top right';
            body.style.webkitTransformOrigin = 'top right';
            
            body.style.width = (100 / $zoomLevel) + '%';
            body.style.height = (100 / $zoomLevel) + '%';
            
            body.style.overflow = 'auto';
            html.style.overflow = 'auto';
            
            console.log('✅ iOS zoom applied: scale(' + $zoomLevel + ')');
          })();
        ''');
      } else {
        await controller!.runJavaScript('''
          (function() {
            var html = document.documentElement;
            var body = document.body;
            
            html.style.transformOrigin = '0 0';
            body.style.transformOrigin = '0 0';
            
            html.style.transform = 'scale($zoomLevel)';
            html.style.width = (100 / $zoomLevel) + '%';
            
            body.style.width = '100%';
            body.style.minHeight = '100vh';
            
            console.log('✅ CSS transform zoom applied: $zoomLevel');
          })();
        ''');
      }
      debugPrint('✅ Zoom applied successfully: $zoomLevel');
    } catch (e) {
      debugPrint('❌ Error applying zoom: $e');
    }
  }

  Future<void> _hideNotificationsOnLoginPage() async {
    if (controller == null) return;

    debugPrint('🔕 Hiding notifications on login page...');

    try {
      await controller!.runJavaScript('''
        (function() {
          console.log('Notification blocker loading...');
          
          var notifications = document.querySelectorAll('.alert, .notification, .toast, [role="alert"], .flash-message, .alert-success, .alert-danger, .alert-warning, .alert-info');
          notifications.forEach(function(notif) {
            notif.style.display = 'none';
          });
          
          console.log('✅ Notifications hidden on login page');
        })();
      ''');

      debugPrint('✅ Notifications hidden');
    } catch (e) {
      debugPrint('⚠️ Error hiding notifications: $e');
    }
  }

  Future<void> _injectAndroidFix() async {
    if (controller == null) return;

    debugPrint('💉 Injecting Android fix for HTML downloads');

    const String jsCode = '''
      (function() {
        console.log('Android WebView fix loading...');
        
        var originalOpen = window.open;
        
        window.open = function(url, name, specs) {
          console.log('Intercepted window.open:', url);
          
          if (url) {
            var cleanUrl = url.replace(/[?&]download=1/, '');
            console.log('Cleaned URL:', cleanUrl);
            
            if (cleanUrl !== window.location.href) {
              window.location.href = cleanUrl;
            }
            return window;
          }
          
          return originalOpen.call(window, url, name, specs);
        };
        
        console.log('Android WebView fix injected successfully');
      })();
    ''';

    try {
      await controller!.runJavaScript(jsCode);
      debugPrint('✅ Android fix injected successfully');
    } catch (e) {
      debugPrint('❌ Error injecting JavaScript: $e');
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        debugPrint('📱 Android SDK: $sdkInt');

        if (sdkInt >= 29) {
          debugPrint(
              '✅ Android 10+ detected - using MediaStore (no permissions required)');
          return true;
        }

        debugPrint('📱 Android 9 or below - requesting storage permission...');

        final status = await Permission.storage.status;
        if (status.isGranted) {
          debugPrint('✅ Storage permission already granted');
          return true;
        }

        final result = await Permission.storage.request();
        if (result.isGranted) {
          debugPrint('✅ Storage permission granted');
          return true;
        }

        debugPrint('❌ Storage permission denied');
        return false;
      } catch (e) {
        debugPrint('❌ Permission check error: $e');
        try {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          if (androidInfo.version.sdkInt >= 29) {
            debugPrint('✅ Android 10+ - proceeding without permissions');
            return true;
          }
        } catch (e2) {
          debugPrint('❌ Failed to check Android version: $e2');
        }
        return false;
      }
    }

    debugPrint('✅ iOS - no permission needed');
    return true; // iOS
  }

  Future<Uint8List> _captureWebView() async {
    if (Platform.isIOS) {
      final bytes = await _channel.invokeMethod('takeSnapshot');
      return Uint8List.fromList(List<int>.from(bytes));
    }

    RenderRepaintBoundary boundary =
        _webViewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image img = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _savePageAsImage() async {
    try {
      debugPrint('📸 Starting screenshot capture...');

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

      Uint8List screenshot;

      try {
        screenshot = await _captureWebView();
      } catch (e) {
        debugPrint('❌ WebView capture failed: $e');

        try {
          debugPrint('🔄 Trying alternative capture method...');

          RenderBox? renderBox =
              _webViewKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox == null) {
            throw Exception('RenderBox not found');
          }

          final size = renderBox.size;
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder,
              Rect.fromPoints(Offset.zero, Offset(size.width, size.height)));

          canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
              Paint()..color = Colors.white);

          renderBox.paint(canvas as PaintingContext, Offset.zero);

          final picture = recorder.endRecording();
          final image =
              await picture.toImage(size.width.toInt(), size.height.toInt());
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);

          if (byteData == null) {
            throw Exception('Could not convert alternative image to byte data');
          }

          screenshot = byteData.buffer.asUint8List();
          debugPrint(
              '✅ Alternative capture successful: ${screenshot.length} bytes');
        } catch (e2) {
          debugPrint('❌ Alternative capture also failed: $e2');
          throw Exception('All capture methods failed');
        }
      }

      if (screenshot.isEmpty) {
        _showMessage('فشل التقاط الصورة - الرجاء المحاولة مرة أخرى');
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        return;
      }

      debugPrint('💾 Saving screenshot to gallery...');

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'salary_slip_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(screenshot);

      try {
        await Gal.putImage(tempFile.path, album: 'قسائم الرواتب');
        debugPrint('✅ Image saved to gallery successfully');

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
        debugPrint('❌ Error saving to gallery: $e');

        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        _showMessage('فشل حفظ الصورة في المعرض');
      }
    } catch (e) {
      debugPrint('❌ Error saving screenshot: $e');

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
      debugPrint('⬅️ Going back in WebView history');
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
                onPressed: () => Navigator.pop(context, false),
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
    debugPrint(
        '🎨 Building WebViewScreen - isLoading: $isLoading, hasError: $hasError, isLoggedIn: $isLoggedIn');

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (canGoBack && controller != null) {
                debugPrint('⬅️ Back button pressed - Going back in WebView');
                controller!.goBack();
              } else {
                debugPrint('🚪 Back button pressed - Showing exit dialog');
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
                debugPrint('🔔 Notifications icon tapped');
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
