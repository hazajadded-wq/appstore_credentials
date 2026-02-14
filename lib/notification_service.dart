import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'notification_database.dart';

/// NotificationService - WhatsApp/Telegram style notification persistence
class NotificationService {
  // ============================================
  // CONFIGURATION
  // ============================================
  static const String baseUrl = 'https://lpgaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';

  static bool _isInitialized = false;
  static StreamController<int>? _unreadCountController;
  static Timer? _syncTimer;

  // ============================================
  // INITIALIZATION
  // ============================================
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await NotificationDatabase.instance
        .customSelect('SELECT 1')
        .get(); // Initialize DB

    _unreadCountController = StreamController<int>.broadcast();
    _startPeriodicSync();

    _isInitialized = true;
    debugPrint('🚀 [NotificationService] Initialized with SQLite');
  }

  static Stream<int> get unreadCountStream =>
      _unreadCountController?.stream ?? Stream.value(0);

  // ============================================
  // WHATSAPP-STYLE IMMEDIATE SAVING
  // ============================================

  static Future<void> saveNotificationImmediately(
      Map<String, dynamic> notification) async {
    try {
      final companion = NotificationDataExtension.fromJson(notification);

      // Save to local database immediately
      await NotificationDatabase.instance.insertOrUpdateNotification(companion);

      // Save to server in background (don't await)
      _saveToServerAsync(notification);

      // Update unread count
      await _updateUnreadCount();

      debugPrint(
          '✅ [NotificationService] Saved notification immediately: ${notification['id']}');
    } catch (e) {
      debugPrint('❌ [NotificationService] Failed to save immediately: $e');
      // Try server save anyway
      _saveToServerAsync(notification);
    }
  }

  static Future<void> _saveToServerAsync(
      Map<String, dynamic> notification) async {
    try {
      await saveNotificationToServer(notification);
      debugPrint(
          '✅ [NotificationService] Server save successful for: ${notification['id']}');
    } catch (e) {
      debugPrint('⚠️ [NotificationService] Server save failed, will retry: $e');
      // Could implement retry queue here
    }
  }

  // ============================================
  // SERVER SYNC (WhatsApp-style background sync)
  // ============================================

  static Future<List<Map<String, dynamic>>>
      getAllNotificationsFromServer() async {
    try {
      if (!await hasInternetConnection()) {
        debugPrint('📡 [NotificationService] No internet, using local only');
        return await getLocalNotifications();
      }

      final response = await http.get(
        Uri.parse('$apiEndpoint?action=get_all&limit=500'), // Get more for sync
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['notifications'] != null) {
          final serverNotifications =
              List<Map<String, dynamic>>.from(data['notifications']);

          // Sync with local database
          await _syncWithLocalDatabase(serverNotifications);

          debugPrint(
              '✅ [NotificationService] Synced ${serverNotifications.length} from server');
          return serverNotifications;
        }
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Server sync failed: $e');
    }

    // Fallback to local
    return await getLocalNotifications();
  }

  static Future<void> _syncWithLocalDatabase(
      List<Map<String, dynamic>> serverNotifications) async {
    try {
      final companions = serverNotifications
          .map((n) => NotificationDataExtension.fromJson(n))
          .toList();
      await NotificationDatabase.instance.bulkInsertNotifications(companions);

      // Clean up old notifications
      await NotificationDatabase.instance.deleteOldNotifications(keepLast: 300);

      await _updateUnreadCount();
      debugPrint(
          '💾 [NotificationService] Synced ${serverNotifications.length} to local DB');
    } catch (e) {
      debugPrint('❌ [NotificationService] Local sync failed: $e');
    }
  }

  // ============================================
  // LOCAL DATABASE OPERATIONS
  // ============================================

  static Future<List<Map<String, dynamic>>> getLocalNotifications({
    int limit = 200,
    String? type,
    bool? isRead,
  }) async {
    try {
      final notifications =
          await NotificationDatabase.instance.getAllNotifications(
        limit: limit,
        type: type,
        isRead: isRead,
      );

      final result = notifications.map((n) => n.toJson()).toList();
      debugPrint(
          '📂 [NotificationService] Loaded ${result.length} from local DB');
      return result;
    } catch (e) {
      debugPrint('❌ [NotificationService] Local load failed: $e');
      return [];
    }
  }

  static Future<int> getUnreadCount() async {
    try {
      return await NotificationDatabase.instance.getUnreadCount();
    } catch (e) {
      debugPrint('❌ [NotificationService] Unread count failed: $e');
      return 0;
    }
  }

  static Future<void> _updateUnreadCount() async {
    final count = await getUnreadCount();
    _unreadCountController?.add(count);
  }

  // ============================================
  // USER ACTIONS
  // ============================================

  static Future<bool> markAsRead(String notificationId) async {
    try {
      final success =
          await NotificationDatabase.instance.markAsRead(notificationId);
      if (success) {
        await _updateUnreadCount();

        // Update server in background
        _markAsReadOnServer(notificationId);
      }
      return success;
    } catch (e) {
      debugPrint('❌ [NotificationService] Mark as read failed: $e');
      return false;
    }
  }

  static Future<bool> deleteNotification(String notificationId) async {
    try {
      final deleted = await NotificationDatabase.instance
          .deleteNotification(notificationId);
      if (deleted > 0) {
        await _updateUnreadCount();
        // Could delete from server too if needed
      }
      return deleted > 0;
    } catch (e) {
      debugPrint('❌ [NotificationService] Delete failed: $e');
      return false;
    }
  }

  static Future<void> clearAllNotifications() async {
    try {
      await NotificationDatabase.instance.clearAll();
      await _updateUnreadCount();
      debugPrint('🗑️ [NotificationService] Cleared all notifications');
    } catch (e) {
      debugPrint('❌ [NotificationService] Clear failed: $e');
    }
  }

  // ============================================
  // SERVER OPERATIONS
  // ============================================

  static Future<bool> hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> saveNotificationToServer(
      Map<String, dynamic> notification) async {
    try {
      if (!await hasInternetConnection()) return false;

      final response = await http.post(
        Uri.parse(apiEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'action': 'save_notification',
          'id': notification['id']?.toString() ?? '',
          'title': notification['title'] ?? '',
          'body': notification['body'] ?? '',
          'image_url':
              notification['imageUrl'] ?? notification['image_url'] ?? '',
          'type': notification['type'] ?? 'general',
          'data_payload': jsonEncode(notification['data'] ?? {}),
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [NotificationService] Server save error: $e');
      return false;
    }
  }

  static Future<void> _markAsReadOnServer(String notificationId) async {
    try {
      if (!await hasInternetConnection()) return;

      await http.post(
        Uri.parse(apiEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'action': 'mark_as_read',
          'id': notificationId,
        },
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Silently fail for read status
    }
  }

  // ============================================
  // PERIODIC SYNC (WhatsApp-style)
  // ============================================

  static void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      debugPrint('⏰ [NotificationService] Periodic sync with server');
      getAllNotificationsFromServer();
    });
  }

  static void dispose() {
    _syncTimer?.cancel();
    _unreadCountController?.close();
  }

  // ============================================
  // UTILITY METHODS
  // ============================================

  static Future<void> forceSyncNow() async {
    debugPrint('🔄 [NotificationService] Force sync requested');
    await getAllNotificationsFromServer();
  }

  static Future<Map<String, dynamic>> getStats() async {
    try {
      final total = await NotificationDatabase.instance.getTotalCount();
      final unread = await NotificationDatabase.instance.getUnreadCount();
      final read = total - unread;

      return {
        'total': total,
        'unread': unread,
        'read': read,
      };
    } catch (e) {
      return {'total': 0, 'unread': 0, 'read': 0};
    }
  }
}
