import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// NotificationService - Client for PHP/MySQL notifications API.
class NotificationService {
  // ============================================
  // API CONFIGURATION
  // ============================================
  static const String baseUrl = 'https://lpgaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final_v2';

  static bool _isInitialized = false;
  static List<Map<String, dynamic>> _pendingServerSync = [];

  // ============================================
  // Initialize service
  // ============================================
  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('🚀 [NotificationService] Initialized');
  }

  // ============================================
  // Check internet connectivity
  // ============================================
  static Future<bool> hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      debugPrint('⚠️ [NotificationService] Connectivity check failed: $e');
      return false;
    }
  }

  // ============================================
  // CRITICAL FIXED: Get all notifications from MySQL
  // Using GET request with proper parameters
  // ============================================
  static Future<List<Map<String, dynamic>>> getAllNotifications({
    int limit = 100,
  }) async {
    try {
      if (!await hasInternetConnection()) {
        debugPrint('📡 [NotificationService] No internet connection');
        return [];
      }

      debugPrint(
          '📡 [NotificationService] Fetching from: $apiEndpoint?action=get_all&limit=$limit');

      final response = await http.get(
        Uri.parse('$apiEndpoint?action=get_all&limit=$limit'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint(
          '📥 [NotificationService] Response status: ${response.statusCode}');
      debugPrint(
          '📥 [NotificationService] Response body: ${response.body.substring(0, min(200, response.body.length))}...');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['notifications'] != null) {
          final notifications =
              List<Map<String, dynamic>>.from(data['notifications']);
          debugPrint(
              '✅ [NotificationService] Received ${notifications.length} notifications');

          // Save to local disk
          await _mergeWithLocal(notifications);

          return notifications;
        } else {
          debugPrint(
              '⚠️ [NotificationService] Server response: success=${data['success']}');
        }
      } else {
        debugPrint(
            '❌ [NotificationService] HTTP Error: ${response.statusCode}');
      }
    } catch (e, stacktrace) {
      debugPrint('❌ [NotificationService] Network Error: $e');
      debugPrint('❌ [NotificationService] Stacktrace: $stacktrace');
    }

    return [];
  }

  // ============================================
  // CRITICAL: Merge server notifications with local
  // Preserve read status from local storage
  // ============================================
  static Future<void> _mergeWithLocal(
      List<Map<String, dynamic>> serverNotifications) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);
      List<Map<String, dynamic>> localList = [];

      if (jsonStr != null) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        localList = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      // Create map of local notifications with their read status
      final Map<String, Map<String, dynamic>> localMap = {};
      for (var item in localList) {
        final id = item['id'].toString();
        localMap[id] = item;
      }

      // Merge server notifications with local read status
      final Map<String, Map<String, dynamic>> mergedMap = {};

      // Add all server notifications
      for (var serverItem in serverNotifications) {
        final id = serverItem['id'].toString();
        final localItem = localMap[id];

        if (localItem != null) {
          // Preserve read status from local
          serverItem['isRead'] = localItem['isRead'] ?? false;
        } else {
          serverItem['isRead'] = false;
        }

        mergedMap[id] = serverItem;
      }

      // Add local notifications that might not be in server yet
      for (var localItem in localList) {
        final id = localItem['id'].toString();
        if (!mergedMap.containsKey(id)) {
          mergedMap[id] = localItem;
        }
      }

      // Convert back to list and sort by timestamp
      List<Map<String, dynamic>> mergedList = mergedMap.values.toList();
      mergedList.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        if (aTime is int && bTime is int) {
          return bTime.compareTo(aTime);
        }
        return 0;
      });

      // Limit to 200
      if (mergedList.length > 200) {
        mergedList = mergedList.sublist(0, 200);
      }

      // Save back to disk
      await prefs.setString(storageKey, jsonEncode(mergedList));
      debugPrint(
          '💾 [NotificationService] Merged ${mergedList.length} notifications');
    } catch (e) {
      debugPrint('❌ [NotificationService] Merge failed: $e');
    }
  }

  // ============================================
  // CRITICAL iOS FIX: Save to Local Disk (Immediate Write)
  // Used by background handler to store notifications
  // iOS OPTIMIZATION: Force immediate write with reload before and after
  // EXTRA: Multiple verification steps for force-closed apps
  // ============================================
  static Future<void> saveToLocalDisk(
      Map<String, dynamic> newNotificationJson) async {
    try {
      debugPrint('💾 [NotificationService] Starting save for: ${newNotificationJson['id']}');
      
      final prefs = await SharedPreferences.getInstance();
      
      // CRITICAL iOS FIX: Force reload to get latest data
      await prefs.reload();
      debugPrint('🔄 [NotificationService] SharedPreferences reloaded');

      // Get existing list
      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];
      debugPrint('📂 [NotificationService] Current list size: ${list.length}');

      // Add new item to TOP of list
      final newId = newNotificationJson['id'].toString();

      // Remove if exists (deduplicate)
      list.removeWhere((item) => item['id'].toString() == newId);

      // Insert at top
      list.insert(0, newNotificationJson);

      // Limit to 200
      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      // CRITICAL iOS FIX: Save with error handling
      bool success = false;
      int attempts = 0;
      while (!success && attempts < 3) {
        attempts++;
        success = await prefs.setString(storageKey, jsonEncode(list));
        if (!success) {
          debugPrint('⚠️ [NotificationService] Save attempt $attempts failed, retrying...');
          await Future.delayed(Duration(milliseconds: 100 * attempts));
        }
      }
      
      debugPrint('💾 [NotificationService] Save result: $success (attempts: $attempts)');
      
      if (!success) {
        debugPrint('❌ [NotificationService] Failed to save after $attempts attempts');
        return;
      }
      
      // CRITICAL iOS FIX: Reload again to ensure it's written
      await prefs.reload();
      
      // EXTRA: Wait for iOS to finish writing (reduced to 50ms)
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Verify the save
      final verifyStr = prefs.getString(storageKey);
      if (verifyStr != null) {
        final verifyList = jsonDecode(verifyStr);
        final found = verifyList.any((item) => item['id'].toString() == newId);
        debugPrint('✅ [NotificationService] Verified notification $newId saved: $found');
        debugPrint('💾 [NotificationService] Total stored: ${verifyList.length}');
      } else {
        debugPrint('⚠️ [NotificationService] Verification failed - no data found');
      }

      // Try to sync to server if we have connection
      if (await hasInternetConnection()) {
        saveNotificationToServer(newNotificationJson);
      } else {
        _pendingServerSync.add(newNotificationJson);
        if (_pendingServerSync.length > 50) {
          _pendingServerSync =
              _pendingServerSync.sublist(_pendingServerSync.length - 50);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [NotificationService] Save Failed: $e');
      debugPrint('❌ [NotificationService] StackTrace: $stackTrace');
    }
  }

  // ============================================
  // Save notification to server
  // CRITICAL: Primary storage method for iOS
  // ============================================
  static Future<bool> saveNotificationToServer(
      Map<String, dynamic> notification) async {
    try {
      if (!await hasInternetConnection()) {
        debugPrint('⚠️ [NotificationService] No internet for server save');
        return false;
      }

      debugPrint('🌐 [NotificationService] Saving to server: ${notification['id']}');

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
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['success'] == true;
        debugPrint('✅ [NotificationService] Server save: $success');
        return success;
      }
      
      debugPrint('⚠️ [NotificationService] Server responded with: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ [NotificationService] Server save error: $e');
      return false;
    }
  }

  // ============================================
  // CRITICAL iOS FIX: Get local notifications with forced reload
  // ============================================
  static Future<List<Map<String, dynamic>>> getLocalNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // CRITICAL iOS FIX: Always reload to get latest data
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final notifications =
            list.map((e) => Map<String, dynamic>.from(e)).toList();
        debugPrint(
            '📂 [NotificationService] Loaded ${notifications.length} from disk');
        return notifications;
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Load failed: $e');
    }

    return [];
  }

  // ============================================
  // Mark notification as read
  // ============================================
  static Future<void> markAsRead(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null) {
        List<dynamic> list = jsonDecode(jsonStr);
        bool updated = false;

        for (var item in list) {
          if (item['id'].toString() == id) {
            if (item['isRead'] != true) {
              item['isRead'] = true;
              updated = true;
            }
            break;
          }
        }

        if (updated) {
          await prefs.setString(storageKey, jsonEncode(list));
          await prefs.reload(); // iOS FIX
          debugPrint('✅ [NotificationService] Marked $id as read');
        }
      }

      // Try to sync to server in background
      if (await hasInternetConnection()) {
        _markAsReadOnServer(id);
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Mark as read error: $e');
    }
  }

  static Future<void> _markAsReadOnServer(String id) async {
    try {
      await http.post(
        Uri.parse(apiEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'action': 'mark_as_read',
          'id': id,
        },
      );
    } catch (e) {
      // Silently fail
    }
  }

  // ============================================
  // Delete notification
  // ============================================
  static Future<void> deleteNotification(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null) {
        List<dynamic> list = jsonDecode(jsonStr);
        list.removeWhere((item) => item['id'].toString() == id);
        await prefs.setString(storageKey, jsonEncode(list));
        await prefs.reload(); // iOS FIX
        debugPrint('🗑️ [NotificationService] Deleted $id');
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Delete error: $e');
    }
  }

  // ============================================
  // Clear all notifications
  // ============================================
  static Future<void> clearAllNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      await prefs.reload(); // iOS FIX
      debugPrint('✅ [NotificationService] Cleared all notifications');
    } catch (e) {
      debugPrint('❌ [NotificationService] Clear failed: $e');
    }
  }

  // ============================================
  // Get unread count
  // ============================================
  static Future<int> getUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final unreadCount = list.where((item) => item['isRead'] != true).length;
        return unreadCount;
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Unread count error: $e');
    }

    return 0;
  }

  // ============================================
  // Sync pending to server
  // ============================================
  static Future<void> syncPendingToServer() async {
    if (_pendingServerSync.isEmpty) return;
    if (!await hasInternetConnection()) return;

    final List<Map<String, dynamic>> synced = [];
    for (var notification in _pendingServerSync) {
      final success = await saveNotificationToServer(notification);
      if (success) {
        synced.add(notification);
      }
    }

    for (var notification in synced) {
      _pendingServerSync.remove(notification);
    }

    debugPrint('✅ [NotificationService] Synced ${synced.length} notifications');
  }
}

int min(int a, int b) => a < b ? a : b;
