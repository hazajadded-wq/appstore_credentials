import 'package:flutter/foundation.dart';
import 'local_database_service.dart';
import 'notification_service.dart';
import 'dart:convert';

/// ============================================
/// NOTIFICATION MANAGER - LOCAL FIRST
/// Display from SQLite immediately
/// Sync with server in background
/// ============================================
class NotificationManager extends ChangeNotifier {
  static final NotificationManager instance = NotificationManager._();
  NotificationManager._();

  List<NotificationItem> _notifications = [];
  int _unreadCount = 0;
  bool _isInitialized = false;

  List<NotificationItem> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isInitialized => _isInitialized;

  // ============================================
  // INITIALIZE - Load from SQLite immediately
  // ============================================
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('');
    print('🚀 [Manager] ========================================');
    print('🚀 [Manager] INITIALIZING - LOCAL FIRST');
    print('🚀 [Manager] ========================================');

    // 1️⃣ Load from SQLite IMMEDIATELY
    await _loadFromLocal();

    // 2️⃣ Sync with server in background (don't wait)
    _syncWithServerBackground();

    _isInitialized = true;

    print('🚀 [Manager] Initialization complete');
    print('');
  }

  // ============================================
  // LOAD FROM LOCAL - Instant display
  // ============================================
  Future<void> _loadFromLocal() async {
    try {
      final data = await LocalDatabaseService.getAll(limit: 200);

      _notifications = data
          .map((item) => NotificationItem(
                id: item['id'] ?? '',
                title: item['title'] ?? '',
                body: item['body'] ?? '',
                type: item['type'] ?? 'general',
                imageUrl: item['imageUrl'],
                timestamp:
                    DateTime.fromMillisecondsSinceEpoch(item['timestamp'] ?? 0),
                isRead: item['isRead'] ?? false,
                data: item['data'] ?? {},
              ))
          .toList();

      _unreadCount = await LocalDatabaseService.getUnreadCount();

      print('📂 [Manager] Loaded ${_notifications.length} from SQLite');
      print('📊 [Manager] Unread: $_unreadCount');

      notifyListeners();
    } catch (e) {
      print('❌ [Manager] Load from local error: $e');
    }
  }

  // ============================================
  // ADD NOTIFICATION (from foreground/background)
  // ============================================
  Future<void> addNotification(NotificationItem item) async {
    try {
      // 1️⃣ Save to SQLite first
      final saved = await LocalDatabaseService.insert(item.toJson());

      if (!saved) {
        print('⚠️ [Manager] Notification ${item.id} already exists');
        return;
      }

      // 2️⃣ Update UI immediately
      _notifications.insert(0, item);
      if (!item.isRead) {
        _unreadCount++;
      }

      // Limit to 200
      if (_notifications.length > 200) {
        _notifications = _notifications.sublist(0, 200);
      }

      notifyListeners();
      print('✅ [Manager] Added notification: ${item.id}');

      // 3️⃣ Send to server in background (don't wait)
      _sendToServerBackground(item);
    } catch (e) {
      print('❌ [Manager] Add notification error: $e');
    }
  }

  // ============================================
  // SYNC WITH SERVER - Background only
  // Merge new notifications from server
  // ============================================
  Future<void> _syncWithServerBackground() async {
    try {
      print('🔄 [Manager] Silent sync with server...');

      final serverList =
          await NotificationService.getAllNotifications(limit: 100);

      if (serverList.isEmpty) {
        print('⚠️ [Manager] Server returned 0 notifications');
        return;
      }

      int newCount = 0;

      for (final serverItem in serverList) {
        final id = serverItem['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        // Check if exists locally
        final exists = await LocalDatabaseService.exists(id);

        if (!exists) {
          // New notification from server - add it
          final item = NotificationItem.fromMySQL(serverItem);

          await LocalDatabaseService.insert(item.toJson());
          _notifications.insert(0, item);

          if (!item.isRead) {
            _unreadCount++;
          }

          newCount++;
        }
      }

      if (newCount > 0) {
        // Limit to 200
        if (_notifications.length > 200) {
          _notifications = _notifications.sublist(0, 200);
        }

        notifyListeners();
        print('✅ [Manager] Synced $newCount new notifications from server');
      } else {
        print('✅ [Manager] Server sync complete - no new notifications');
      }
    } catch (e) {
      print('❌ [Manager] Server sync error: $e');
      // Don't fail - local data is still valid
    }
  }

  // ============================================
  // SEND TO SERVER - Background only
  // ============================================
  Future<void> _sendToServerBackground(NotificationItem item) async {
    try {
      final success =
          await NotificationService.saveNotificationToServer(item.toJson());

      if (success) {
        await LocalDatabaseService.markAsSynced(item.id);
        print('✅ [Manager] Sent to server: ${item.id}');
      } else {
        print('⚠️ [Manager] Failed to send to server: ${item.id}');
        // Will retry later via queue
      }
    } catch (e) {
      print('❌ [Manager] Send to server error: $e');
      // Queue will handle retry
    }
  }

  // ============================================
  // SYNC QUEUE - Retry unsynced notifications
  // ============================================
  Future<void> syncQueue() async {
    try {
      final unsynced = await LocalDatabaseService.getUnsynced();

      if (unsynced.isEmpty) return;

      print('🔄 [Manager] Syncing queue: ${unsynced.length} items');

      for (final item in unsynced) {
        try {
          final success =
              await NotificationService.saveNotificationToServer(item);

          if (success) {
            await LocalDatabaseService.markAsSynced(item['id']);
          }
        } catch (e) {
          // Continue with next item
        }
      }

      print('✅ [Manager] Queue sync complete');
    } catch (e) {
      print('❌ [Manager] Queue sync error: $e');
    }
  }

  // ============================================
  // MARK AS READ
  // ============================================
  Future<void> markAsRead(String id) async {
    try {
      await LocalDatabaseService.markAsRead(id);

      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1 && !_notifications[index].isRead) {
        _notifications[index].isRead = true;
        _unreadCount--;
        notifyListeners();
      }

      print('✅ [Manager] Marked as read: $id');
    } catch (e) {
      print('❌ [Manager] Mark as read error: $e');
    }
  }

  // ============================================
  // MARK ALL AS READ
  // ============================================
  Future<void> markAllAsRead() async {
    try {
      for (final notification in _notifications) {
        if (!notification.isRead) {
          await LocalDatabaseService.markAsRead(notification.id);
          notification.isRead = true;
        }
      }

      _unreadCount = 0;
      notifyListeners();

      print('✅ [Manager] Marked all as read');
    } catch (e) {
      print('❌ [Manager] Mark all as read error: $e');
    }
  }

  // ============================================
  // DELETE NOTIFICATION
  // ============================================
  Future<void> deleteNotification(String id) async {
    try {
      await LocalDatabaseService.delete(id);

      _notifications.removeWhere((n) => n.id == id);
      _unreadCount = await LocalDatabaseService.getUnreadCount();

      notifyListeners();

      print('✅ [Manager] Deleted notification: $id');
    } catch (e) {
      print('❌ [Manager] Delete notification error: $e');
    }
  }

  // ============================================
  // CLEAR ALL
  // ============================================
  Future<void> clearAll() async {
    try {
      await LocalDatabaseService.clearAll();

      _notifications.clear();
      _unreadCount = 0;

      notifyListeners();

      print('✅ [Manager] Cleared all notifications');
    } catch (e) {
      print('❌ [Manager] Clear all error: $e');
    }
  }

  // ============================================
  // REFRESH - Manual sync
  // ============================================
  Future<void> refresh() async {
    await _syncWithServerBackground();
  }
}

/// ============================================
/// NOTIFICATION ITEM MODEL
/// ============================================
class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final String? imageUrl;
  final DateTime timestamp;
  bool isRead;
  final Map<String, dynamic> data;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.imageUrl,
    required this.timestamp,
    this.isRead = false,
    this.data = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'imageUrl': imageUrl,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isRead': isRead,
      'data': data,
    };
  }

  factory NotificationItem.fromFirebaseMessage(dynamic message) {
    final messageId =
        message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final notification = message.notification;
    final data = message.data ?? {};

    return NotificationItem(
      id: messageId,
      title: notification?.title ?? data['title'] ?? '',
      body: notification?.body ?? data['body'] ?? '',
      type: data['type'] ?? 'general',
      imageUrl: notification?.android?.imageUrl ?? data['image_url'],
      timestamp: DateTime.now(),
      data: data,
    );
  }

  factory NotificationItem.fromMySQL(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ??
          json['firebase_message_id']?.toString() ??
          '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      type: json['type'] ?? 'general',
      imageUrl: json['image_url'],
      timestamp: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'])
          : DateTime.now(),
      data: json['data_payload'] != null
          ? (json['data_payload'] is String
              ? jsonDecode(json['data_payload'])
              : json['data_payload'])
          : {},
    );
  }
}
