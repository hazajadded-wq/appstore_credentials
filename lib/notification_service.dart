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
      ).timeout(const Duration(seconds: 30));

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
  // FIXED: Sort by sent_at instead of timestamp
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

      // Convert back to list and sort by sent_at (CRITICAL FIX)
      List<Map<String, dynamic>> mergedList = mergedMap.values.toList();
      mergedList.sort((a, b) {
        final aTime = DateTime.tryParse(a['sent_at'] ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['sent_at'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
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
  // CRITICAL: Save to Local Disk - WITH EXTENSIVE LOGGING
  // Used by background handler to store notifications
  // ============================================
  static Future<void> saveToLocalDisk(
      Map<String, dynamic> newNotificationJson) async {
    print('💾 ========================================');
    print('💾 [NotificationService] SAVE TO LOCAL DISK');
    print('💾 ========================================');

    try {
      print('💾 [Service] Notification to save:');
      print('   - ID: ${newNotificationJson['id']}');
      print('   - Title: ${newNotificationJson['title']}');
      print('   - Body: ${newNotificationJson['body']}');
      print('   - Type: ${newNotificationJson['type']}');

      print('💾 [Service] Step 1: Getting SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      print('✅ [Service] Step 1: Got SharedPreferences');

      print('💾 [Service] Step 2: Reloading preferences...');
      await prefs.reload();
      print('✅ [Service] Step 2: Reloaded');

      print('💾 [Service] Step 3: Reading existing data...');
      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];
      print('✅ [Service] Step 3: Found ${list.length} existing notifications');

      print('💾 [Service] Step 4: Processing new notification...');
      final newId = newNotificationJson['id'].toString();
      print('   - New notification ID: $newId');

      print('💾 [Service] Step 5: Removing duplicates...');
      final beforeCount = list.length;
      list.removeWhere((item) => item['id'].toString() == newId);
      final afterCount = list.length;
      if (beforeCount != afterCount) {
        print('   - Removed ${beforeCount - afterCount} duplicate(s)');
      } else {
        print('   - No duplicates found');
      }

      print('💾 [Service] Step 6: Inserting at top...');
      list.insert(0, newNotificationJson);
      print('✅ [Service] Step 6: Inserted. Total now: ${list.length}');

      print('💾 [Service] Step 7: Limiting to 200...');
      if (list.length > 200) {
        list = list.sublist(0, 200);
        print('   - Trimmed to 200');
      } else {
        print('   - No trimming needed (${list.length} items)');
      }

      print('💾 [Service] Step 8: Converting to JSON string...');
      final jsonToSave = jsonEncode(list);
      print(
          '✅ [Service] Step 8: JSON string created (${jsonToSave.length} chars)');

      print('💾 [Service] Step 9: SAVING TO SHAREDPREFERENCES...');
      final saveResult = await prefs.setString(storageKey, jsonToSave);
      print('✅✅✅ [Service] Step 9: SAVE RESULT = $saveResult ✅✅✅');

      print('💾 [Service] Step 10: Verifying save...');
      final verification = prefs.getString(storageKey);
      if (verification != null) {
        final verifyList = jsonDecode(verification);
        print(
            '✅✅✅ [Service] Step 10: VERIFIED! ${verifyList.length} notifications in storage ✅✅✅');
        print('   - First notification ID: ${verifyList[0]['id']}');
        print('   - First notification title: ${verifyList[0]['title']}');
      } else {
        print('❌❌❌ [Service] Step 10: VERIFICATION FAILED! ❌❌❌');
      }

      print('💾 ========================================');
      print('💾 [Service] SAVE COMPLETED SUCCESSFULLY');
      print('💾 Total notifications stored: ${list.length}');
      print('💾 ========================================');

      // Try to sync to server if we have connection
      if (await hasInternetConnection()) {
        print('🌐 [Service] Has internet, syncing to server...');
        saveNotificationToServer(newNotificationJson);
      } else {
        print('📡 [Service] No internet, adding to pending sync');
        _pendingServerSync.add(newNotificationJson);
        if (_pendingServerSync.length > 50) {
          _pendingServerSync =
              _pendingServerSync.sublist(_pendingServerSync.length - 50);
        }
      }
    } catch (e, stackTrace) {
      print('❌❌❌ [Service] SAVE FAILED ❌❌❌');
      print('❌ Error: $e');
      print('❌ Stack trace: $stackTrace');
      print('❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌');
    }
  }

  // ============================================
  // Save notification to server
  // ============================================
  static Future<bool> saveNotificationToServer(
      Map<String, dynamic> notification) async {
    try {
      if (!await hasInternetConnection()) {
        return false;
      }

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
      debugPrint('❌ [NotificationService] Save error: $e');
      return false;
    }
  }

  // ============================================
  // Get local notifications - WITH EXTENSIVE LOGGING
  // ============================================
  static Future<List<Map<String, dynamic>>> getLocalNotifications() async {
    print('📂 ========================================');
    print('📂 [NotificationService] GET LOCAL NOTIFICATIONS');
    print('📂 ========================================');

    try {
      print('📂 [Service] Step 1: Getting SharedPreferences instance...');
      final prefs = await SharedPreferences.getInstance();
      print('✅ [Service] Step 1: Got SharedPreferences');

      print('📂 [Service] Step 2: Reloading preferences...');
      await prefs.reload();
      print('✅ [Service] Step 2: Reloaded');

      print('📂 [Service] Step 3: Reading key "$storageKey"...');
      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null) {
        print(
            '✅ [Service] Step 3: Found data! Length: ${jsonStr.length} chars');

        print('📂 [Service] Step 4: Decoding JSON...');
        final List<dynamic> list = jsonDecode(jsonStr);
        print('✅ [Service] Step 4: Decoded ${list.length} items');

        print('📂 [Service] Step 5: Converting to Map...');
        final notifications =
            list.map((e) => Map<String, dynamic>.from(e)).toList();
        print(
            '✅ [Service] Step 5: Converted ${notifications.length} notifications');

        if (notifications.isNotEmpty) {
          print('📂 [Service] First notification:');
          print('   - ID: ${notifications[0]['id']}');
          print('   - Title: ${notifications[0]['title']}');
          print('   - Type: ${notifications[0]['type']}');
        }

        print('📂 ========================================');
        print('📂 [Service] RETURNING ${notifications.length} NOTIFICATIONS');
        print('📂 ========================================');

        return notifications;
      } else {
        print('⚠️⚠️⚠️ [Service] NO DATA FOUND IN SHAREDPREFERENCES! ⚠️⚠️⚠️');
        print('⚠️ Key "$storageKey" is NULL or empty');
        print('⚠️ This means nothing was saved OR save failed');
      }
    } catch (e, stackTrace) {
      print('❌❌❌ [Service] LOAD FAILED ❌❌❌');
      print('❌ Error: $e');
      print('❌ Stack trace: $stackTrace');
      print('❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌');
    }

    print('📂 [Service] Returning empty list');
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
