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

// ======== تتبع الإشعارات التي تمت معالجتها في الجلسة الحالية =============
final Set<String> _handledNotificationIds = {};

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
  // ✅ جديد: قائمة المعرفات المرتبطة
  final Set<String> associatedIds;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    required this.timestamp,
    required this.data,
    this.isRead = false,
    this.type = 'general',
    Set<String>? associatedIds,
  }) : associatedIds = associatedIds ?? {id};

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
      'associatedIds': associatedIds.toList(),
    };
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    Set<String> assocIds = {};
    if (json['associatedIds'] != null) {
      assocIds = Set<String>.from(
          (json['associatedIds'] as List).map((e) => e.toString()));
    }
    final String mainId = json['id'].toString();
    assocIds.add(mainId);

    return NotificationItem(
      id: mainId,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      imageUrl: json['imageUrl'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(
              json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch)
          .toUtc(),
      data: json['data'] != null ? Map<String, dynamic>.from(json['data']) : {},
      isRead: json['isRead'] ?? false,
      type: json['type'] ?? 'general',
      associatedIds: assocIds,
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

    // ✅ استخدام db_id أو id من data كمعرف رئيسي
    String id = message.data['db_id']?.toString() ??
        message.data['id']?.toString() ??
        message.messageId ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // ✅ جمع كل المعرفات المرتبطة
    Set<String> assocIds = {id};
    if (message.messageId != null) assocIds.add(message.messageId!);
    if (message.data['db_id'] != null) {
      assocIds.add(message.data['db_id'].toString());
    }
    if (message.data['id'] != null) {
      assocIds.add(message.data['id'].toString());
    }

    DateTime timestamp;
    try {
      if (message.data['sent_at'] != null) {
        timestamp = DateTime.parse(message.data['sent_at']).toUtc();
      } else if (message.data['timestamp'] != null) {
        timestamp = DateTime.parse(message.data['timestamp']).toUtc();
      } else if (message.sentTime != null) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(
                message.sentTime!.millisecondsSinceEpoch)
            .toUtc();
      } else {
        timestamp = DateTime.now().toUtc();
      }
    } catch (e) {
      timestamp = DateTime.now().toUtc();
    }

    return NotificationItem(
      id: id,
      title: title,
      body: body,
      imageUrl: imageUrl,
      timestamp: timestamp,
      data: message.data,
      isRead: message.data['is_read'] == '1' || message.data['is_read'] == 1,
      type: message.data['type'] ?? 'general',
      associatedIds: assocIds,
    );
  }

  factory NotificationItem.fromMySQL(Map<String, dynamic> map) {
    Map<String, dynamic> payload = {};
    if (map['data_payload'] != null) {
      if (map['data_payload'] is String &&
          map['data_payload'].toString().isNotEmpty) {
        try {
          payload = jsonDecode(map['data_payload']);
        } catch (e) {}
      } else if (map['data_payload'] is Map) {
        payload = Map<String, dynamic>.from(map['data_payload']);
      }
    }

    DateTime timestamp;
    try {
      timestamp = map['sent_at'] != null
          ? DateTime.parse(map['sent_at']).toUtc()
          : DateTime.now().toUtc();
    } catch (e) {
      timestamp = DateTime.now().toUtc();
    }

    // ✅ جمع كل المعرفات
    Set<String> assocIds = {};
    assocIds.add(map['id'].toString());
    if (map['message_id'] != null && map['message_id'].toString().isNotEmpty) {
      assocIds.add(map['message_id'].toString());
    }
    // ✅ إضافة associated_ids من السيرفر
    if (map['associated_ids'] != null) {
      try {
        final List<dynamic> serverAssocIds = map['associated_ids'] is String
            ? jsonDecode(map['associated_ids'])
            : map['associated_ids'];
        for (var aid in serverAssocIds) {
          if (aid != null && aid.toString().isNotEmpty) {
            assocIds.add(aid.toString());
          }
        }
      } catch (e) {}
    }

    return NotificationItem(
      id: map['id'].toString(),
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      imageUrl: map['image_url'],
      timestamp: timestamp,
      data: payload,
      isRead: false, // سيتم تحديثها من النسخة المحلية
      type: map['type'] ?? 'general',
      associatedIds: assocIds,
    );
  }

  // ✅ Helper: هل هذا الإشعار يطابق معرف معين؟
  bool matchesId(String otherId) {
    return id == otherId || associatedIds.contains(otherId);
  }

  // ✅ Helper: هل هذا الإشعار يطابق إشعار آخر؟
  bool matchesNotification(NotificationItem other) {
    // مطابقة بالمعرفات
    if (associatedIds.intersection(other.associatedIds).isNotEmpty) {
      return true;
    }
    // مطابقة بالمحتوى + التوقيت القريب
    if (title.isNotEmpty &&
        title == other.title &&
        body == other.body &&
        timestamp.difference(other.timestamp).inSeconds.abs() < 60) {
      return true;
    }
    return false;
  }

  // ✅ دمج المعرفات من إشعار آخر
  NotificationItem mergeWith(NotificationItem other,
      {bool preserveReadState = true}) {
    return NotificationItem(
      id: id,
      title: other.timestamp.isAfter(timestamp) ? other.title : title,
      body: other.timestamp.isAfter(timestamp) ? other.body : body,
      imageUrl: other.timestamp.isAfter(timestamp)
          ? (other.imageUrl ?? imageUrl)
          : (imageUrl ?? other.imageUrl),
      timestamp: other.timestamp.isAfter(timestamp)
          ? other.timestamp
          : timestamp,
      data: {...data, ...other.data},
      isRead: preserveReadState ? isRead : other.isRead,
      type: other.timestamp.isAfter(timestamp) ? other.type : type,
      associatedIds: {...associatedIds, ...other.associatedIds},
    );
  }
}

/// =========================
/// NOTIFICATION MANAGER - ✅ مُصحّح بالكامل
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
  // ✅ حفظ حالة القراءة بشكل منفصل ودائم
  Set<String> _readIds = {};

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;
  bool get isSyncing => _isSyncing;

  static const String _storageKey = 'stored_notifications_final';
  static const String _deletedIdsKey = 'deleted_notification_ids';
  static const String _readIdsKey = 'read_notification_ids';

  Future<void> loadNotifications() async {
    int waitCount = 0;
    while (NotificationService.isWriting && waitCount < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(_storageKey);
      final deletedJson = prefs.getString(_deletedIdsKey);
      final readJson = prefs.getString(_readIdsKey);

      // ✅ تحميل حالة القراءة
      if (readJson != null) {
        _readIds = Set<String>.from(jsonDecode(readJson));
      }

      if (deletedJson != null) {
        _deletedIds = Set<String>.from(jsonDecode(deletedJson));
      }

      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List;
        _notifications = list.map((e) => NotificationItem.fromJson(e)).toList();

        // ✅ استعادة حالة القراءة من _readIds
        _applyReadStates();
        _sortAndCount();
        debugPrint('📂 [Manager] Loaded ${_notifications.length} from disk');
      }
    } catch (e) {
      debugPrint('❌ [Manager] Load Error: $e');
    }
  }

  // ✅ جديد: تطبيق حالة القراءة على كل الإشعارات
  void _applyReadStates() {
    for (var notification in _notifications) {
      // تحقق إذا أي من المعرفات المرتبطة موجودة في قائمة المقروء
      if (_readIds.contains(notification.id) ||
          notification.associatedIds.any((id) => _readIds.contains(id))) {
        notification.isRead = true;
      }
    }
  }

  Future<void> fetchFromMySQL() async {
    if (_isSyncing) return;
    _isSyncing = true;
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

      bool hasChanges = false;

      for (var serverItem in serverItems) {
        // تحقق من الحذف بكل المعرفات المرتبطة
        if (_deletedIds.contains(serverItem.id) ||
            serverItem.associatedIds.any((id) => _deletedIds.contains(id))) {
          continue;
        }

        // ✅ بحث ذكي عن الإشعار الموجود
        int existingIndex = _notifications
            .indexWhere((n) => n.matchesNotification(serverItem));

        if (existingIndex != -1) {
          final localItem = _notifications[existingIndex];
          // ✅ دمج مع الحفاظ على حالة القراءة المحلية
          final merged =
              localItem.mergeWith(serverItem, preserveReadState: true);
          if (merged.title != localItem.title ||
              merged.body != localItem.body ||
              merged.associatedIds.length > localItem.associatedIds.length) {
            _notifications[existingIndex] = merged;
            hasChanges = true;
          }
        } else {
          // ✅ إشعار جديد - تحقق من حالة القراءة المحفوظة
          if (_readIds.contains(serverItem.id) ||
              serverItem.associatedIds
                  .any((id) => _readIds.contains(id))) {
            serverItem.isRead = true;
          }
          _notifications.add(serverItem);
          hasChanges = true;
        }
      }

      // إزالة المحذوفة
      _notifications.removeWhere((n) =>
          _deletedIds.contains(n.id) ||
          n.associatedIds.any((id) => _deletedIds.contains(id)));

      _sortAndCount();

      if (_notifications.length > 200) {
        _notifications = _notifications.take(200).toList();
      }

      if (hasChanges) {
        await _saveToDisk();
      }

      debugPrint(
          '✅ [Manager] MySQL sync completed: ${_notifications.length} notifications');
    } catch (e) {
      debugPrint('❌ [Manager] Sync Error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> addFirebaseMessage(RemoteMessage message) async {
    final messageId = message.messageId ??
        message.data['id']?.toString() ??
        'msg_${DateTime.now().millisecondsSinceEpoch}';

    if (_handledNotificationIds.contains(messageId)) {
      debugPrint(
          '⚠️ [Manager] Message $messageId already processed in session, skipping');
      return;
    }

    final item = NotificationItem.fromFirebaseMessage(message);

    if (item.title.isEmpty ||
        (item.title == 'إشعار جديد' && item.body.isEmpty)) {
      debugPrint('❌ [Manager] Skipping empty notification');
      return;
    }

    if (_deletedIds.contains(item.id) ||
        item.associatedIds.any((id) => _deletedIds.contains(id))) {
      debugPrint('❌ [Manager] Skipping deleted notification ${item.id}');
      return;
    }

    _handledNotificationIds.add(messageId);

    int waitCount = 0;
    while (_isSyncing && waitCount < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    await loadNotifications();

    // ✅ بحث ذكي
    final existingIndex =
        _notifications.indexWhere((n) => n.matchesNotification(item));

    if (existingIndex != -1) {
      final existing = _notifications[existingIndex];
      // ✅ دمج مع الحفاظ على حالة القراءة
      _notifications[existingIndex] =
          existing.mergeWith(item, preserveReadState: true);
      _sortAndCount();
      await _saveToDisk();
      notifyListeners();
      debugPrint('✅ [Manager] Merged Firebase notification: ${item.id}');
      return;
    }

    // ✅ تحقق من حالة القراءة المحفوظة
    if (_readIds.contains(item.id) ||
        item.associatedIds.any((id) => _readIds.contains(id))) {
      item.isRead = true;
    }

    _notifications.insert(0, item);
    _sortAndCount();
    await _saveToDisk();
    notifyListeners();
    debugPrint('✅ [Manager] Added new Firebase notification: ${item.id}');
  }

  Future<void> addNotificationFromNative(Map<String, dynamic> data) async {
    final item = NotificationItem.fromJson(data);

    if (_handledNotificationIds.contains(item.id)) {
      debugPrint(
          '⚠️ [Manager] Native notification ${item.id} already processed, skipping');
      return;
    }

    if (item.title.isEmpty ||
        (item.title == 'إشعار جديد' && item.body.isEmpty)) {
      debugPrint('❌ [Manager] Skipping empty notification from native');
      return;
    }

    if (_deletedIds.contains(item.id) ||
        item.associatedIds.any((id) => _deletedIds.contains(id))) {
      debugPrint('❌ [Manager] Skipping deleted native notification ${item.id}');
      return;
    }

    _handledNotificationIds.add(item.id);

    int waitCount = 0;
    while (_isSyncing && waitCount < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    await loadNotifications();

    final existingIndex =
        _notifications.indexWhere((n) => n.matchesNotification(item));

    if (existingIndex != -1) {
      debugPrint(
          '⚠️ [Manager] Native notification ${item.id} already exists, merging');
      final existing = _notifications[existingIndex];
      _notifications[existingIndex] =
          existing.mergeWith(item, preserveReadState: true);
      _sortAndCount();
      await _saveToDisk();
      notifyListeners();
      return;
    }

    // ✅ تحقق من حالة القراءة المحفوظة
    if (_readIds.contains(item.id) ||
        item.associatedIds.any((id) => _readIds.contains(id))) {
      item.isRead = true;
    }

    _notifications.insert(0, item);
    _sortAndCount();
    await _saveToDisk();
    notifyListeners();
    debugPrint('✅ [Manager] Added native notification: ${item.id}');
  }

  // ✅ مُصحّح: حفظ حال�� القراءة بشكل دائم ومنفصل
  Future<void> markAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n.matchesId(id));
    if (index != -1 && !_notifications[index].isRead) {
      _notifications[index].isRead = true;

      // ✅ حفظ كل المعرفات المرتبطة كمقروءة
      _readIds.add(_notifications[index].id);
      _readIds.addAll(_notifications[index].associatedIds);

      _updateUnreadCount();
      await _saveToDisk();
      await _saveReadIds();
      notifyListeners();

      debugPrint(
          '✅ [Manager] Marked as read: ${_notifications[index].id} (${_notifications[index].associatedIds.length} associated IDs)');
    }
  }

  // ✅ مُصحّح: تحديد الكل كمقروء
  Future<void> markAllAsRead() async {
    bool changed = false;
    for (var n in _notifications) {
      if (!n.isRead) {
        n.isRead = true;
        _readIds.add(n.id);
        _readIds.addAll(n.associatedIds);
        changed = true;
      }
    }
    if (changed) {
      _updateUnreadCount();
      await _saveToDisk();
      await _saveReadIds();
      notifyListeners();
    }
  }

  Future<void> deleteNotification(String id) async {
    final index = _notifications.indexWhere((n) => n.matchesId(id));
    if (index != -1) {
      final notification = _notifications[index];
      // ✅ حذف كل المعرفات المرتبطة
      _deletedIds.add(notification.id);
      _deletedIds.addAll(notification.associatedIds);
      _notifications.removeAt(index);
    } else {
      _deletedIds.add(id);
    }
    _updateUnreadCount();
    await _saveToDisk();
    notifyListeners();
  }

  Future<void> clearAllNotifications() async {
    for (var n in _notifications) {
      _deletedIds.add(n.id);
      _deletedIds.addAll(n.associatedIds);
    }
    _notifications.clear();
    _updateUnreadCount();
    await _saveToDisk();
    notifyListeners();
  }

  List<NotificationItem> searchNotifications(String query) {
    if (query.isEmpty) return _notifications;
    final q = query.toLowerCase();
    return _notifications
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
  }

  void _sortAndCount() {
    // ✅ إزالة التكرار باستخدام المطابقة الذكية
    final List<NotificationItem> deduped = [];
    for (var notification in _notifications) {
      int existingIndex =
          deduped.indexWhere((n) => n.matchesNotification(notification));
      if (existingIndex == -1) {
        deduped.add(notification);
      } else {
        // دمج مع الحفاظ على حالة القراءة
        final existing = deduped[existingIndex];
        deduped[existingIndex] =
            existing.mergeWith(notification, preserveReadState: true);
      }
    }
    _notifications = deduped;
    _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // ✅ تطبيق حالة القراءة المحفوظة
    _applyReadStates();
    _updateUnreadCount();
  }

  void _updateUnreadCount() {
    _unreadCount = _notifications.where((n) => !n.isRead).length;
  }

  // ✅ جديد: ح��ظ قائمة المعرفات المقروءة بشكل منفصل
  Future<void> _saveReadIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // تحديد حجم أقصى 1000 معرف لتجنب التضخم
      if (_readIds.length > 1000) {
        _readIds = _readIds.toList().sublist(_readIds.length - 1000).toSet();
      }
      await prefs.setString(_readIdsKey, jsonEncode(_readIds.toList()));
      debugPrint('💾 [Manager] Saved ${_readIds.length} read IDs');
    } catch (e) {
      debugPrint('❌ [Manager] Save Read IDs Error: $e');
    }
  }

  Future<void> _saveToDisk() async {
    int waitCount = 0;
    while (NotificationService.isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (waitCount >= 100) {
      debugPrint('⚠️ [Manager] Lock timeout - skipping save');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr =
          jsonEncode(_notifications.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
      await prefs.setString(_deletedIdsKey, jsonEncode(_deletedIds.toList()));
      // ✅ حفظ حالة القراءة مع كل عملية حفظ
      await prefs.setString(_readIdsKey, jsonEncode(_readIds.toList()));

      debugPrint(
          '💾 [Manager] Saved ${_notifications.length} notifications, ${_readIds.length} read IDs');
    } catch (e) {
      debugPrint('❌ [Manager] Save Error: $e');
    }
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
    Future.delayed(const Duration(milliseconds: 300), () {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
      );
    });
  }
}

/// =========================
/// FCM BACKGROUND HANDLER
/// =========================

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('🌙 [BG] Message Received: ${message.messageId}');

  final item = NotificationItem.fromFirebaseMessage(message);

  if (item.title.isEmpty || (item.title == 'إشعار جديد' && item.body.isEmpty)) {
    debugPrint('🌙 [BG] Skipping notification with default/empty title');
    return;
  }

  await Future.delayed(const Duration(milliseconds: 500));
  await NotificationService.saveToLocalDisk(item.toJson());
  debugPrint('🌙 [BG] Notification Saved: ${item.id}');
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

        await Future.delayed(const Duration(milliseconds: 200));
        await NotificationManager.instance.addNotificationFromNative(data);
      } else if (call.method == 'navigateToNotifications') {
        debugPrint('📱 [iOS Channel] Navigation command received');
        Future.delayed(const Duration(milliseconds: 300), () {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) => const NotificationsScreen()),
            (route) => false,
          );
        });
      }
    });
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// =========================
/// APP LIFECYCLE HANDLER
/// =========================

class AppLifecycleHandler extends StatefulWidget {
  final Widget child;
  const AppLifecycleHandler({required this.child, Key? key}) : super(key: key);

  @override
  State<AppLifecycleHandler> createState() => _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends State<AppLifecycleHandler>
    with WidgetsBindingObserver {
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
      debugPrint('📱 [AppLifecycle] App resumed - syncing notifications');
      NotificationManager.instance.fetchFromMySQL();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// =========================
/// MAIN
/// =========================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar_IQ', null);

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    LocalNotificationService.initialize();
    NotificationMethodChannel.setupListener();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await NotificationManager.instance.loadNotifications();

    final messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('🔔 Notification permissions: ${settings.authorizationStatus}');
    await messaging.subscribeToTopic('all_employees');

    final token = await messaging.getToken();
    debugPrint('🔑 FCM Token: $token');

    if (Platform.isAndroid) {
      await _requestIgnoreBatteryOptimizations();
    }

    await _setupNotificationNavigation(messaging);
  } catch (e) {
    debugPrint('❌ Init Error: $e');
  }

  runApp(
    AppLifecycleHandler(
      child: const MyApp(),
    ),
  );
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
  // 1️⃣ Foreground - نحفظ فقط
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('📱 [Foreground] Saving notification...');
    NotificationManager.instance.addFirebaseMessage(message);
  });

  // 2️⃣ Background Click - ننتقل فقط ولا نحفظ
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('👆 [Background Click] Navigating only...');
    _navigateToNotifications();
  });

  // 3️⃣ Terminated Launch - ننتقل فقط ولا نحفظ
  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('🚀 [Terminated Launch] Navigating only...');
    Future.delayed(const Duration(milliseconds: 500), () {
      _navigateToNotifications();
    });
  }
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
      Future.delayed(const Duration(milliseconds: 500), () {
        NotificationManager.instance.loadNotifications().then((_) {
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

/// =========================
/// UI COMPONENTS
/// =========================

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

/// =========================
/// SPLASH SCREEN
/// =========================

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

/// =========================
/// PRIVACY POLICY SCREEN
/// =========================

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

/// =========================
/// NOTIFICATIONS SCREEN
/// =========================

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _forceRefresh();
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
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
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _forceRefresh();
        }
      });
    }
  }

  Future<void> _forceRefresh() async {
    await NotificationManager.instance.loadNotifications();
    await NotificationManager.instance.fetchFromMySQL();

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
                  decoration: InputDecoration(                    hintText: 'البحث في الإشعارات...',
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

            if (!mounted) return;

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
    } catch (e) {}
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
      DateTime now = DateTime.now().toUtc();
      Duration difference = now.difference(timestamp);

      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inMinutes < 60) {
        return 'منذ ${difference.inMinutes} دقيقة';
      } else if (difference.inHours < 24) {
        return 'منذ ${difference.inHours} ساعة';
      } else if (difference.inDays < 7) {
        return 'منذ ${difference.inDays} يوم';
      } else {
        final dateFormat = DateFormat('dd/MM/yyyy', 'ar_IQ');
        return dateFormat.format(timestamp.toLocal());
      }
    } catch (e) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}

/// =========================
/// NOTIFICATION DETAIL SCREEN
/// =========================

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الشركة العامة لتعبئة وخدمات الغاز',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: const Color(0xFF2D3748),
                  ),
                ),
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
    } catch (e) {}
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
      DateTime now = DateTime.now().toUtc();
      Duration difference = now.difference(timestamp);

      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inMinutes < 60) {
        return 'منذ ${difference.inMinutes} دقيقة';
      } else if (difference.inHours < 24) {
        return 'منذ ${difference.inHours} ساعة';
      } else if (difference.inDays < 7) {
        return 'منذ ${difference.inDays} يوم';
      } else {
        final dateFormat = DateFormat('dd/MM/yyyy', 'ar_IQ');
        return dateFormat.format(timestamp.toLocal());
      }
    } catch (e) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}

/// =========================
/// WEBVIEW SCREEN
/// =========================

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
    if (isOnLoginPage) {
      return false;
    }

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
