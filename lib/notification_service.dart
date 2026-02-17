import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NotificationService - Client for PHP/MySQL notifications API.
/// FIXED: No duplicates, proper UTC time handling
class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';

  // CRITICAL: Shared lock to prevent concurrent SharedPreferences access
  static bool _isWriting = false;
  static int _lockWaitCount = 0;
  static final Map<String, int> _lastSavedTimestamps =
      {}; // Track last save time per ID

  // =========================================================
  // Get all notifications from MySQL
  // =========================================================
  static Future<List<Map<String, dynamic>>> getAllNotifications({
    int limit = 100,
  }) async {
    final uri = Uri.parse('$apiEndpoint?action=get_all&limit=$limit');

    try {
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json'
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['notifications'] != null) {
          return List<Map<String, dynamic>>.from(data['notifications']);
        }
      }
    } catch (e) {
      debugPrint('❌ [NotificationService] Network Error: $e');
    }

    return [];
  }

  // =========================================================
  // CRITICAL: Save to Local Disk (Safe for Background)
  // WITH PROPER LOCKING AND DEDUPLICATION
  // =========================================================
  static Future<void> saveToLocalDisk(
      Map<String, dynamic> newNotificationJson) async {
    // VALIDATION: Skip empty notifications
    final title = newNotificationJson['title']?.toString() ?? '';
    final body = newNotificationJson['body']?.toString() ?? '';
    if (title.isEmpty || (title == 'إشعار جديد' && body.isEmpty)) {
      debugPrint('⚠️ [BG-Service] Skipping empty notification');
      return;
    }

    // CRITICAL: Get ID and timestamp
    final String newId = newNotificationJson['id']?.toString() ??
        newNotificationJson['message_id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // Parse timestamp properly
    DateTime newTimestamp;
    try {
      if (newNotificationJson['timestamp'] != null) {
        newTimestamp = DateTime.parse(newNotificationJson['timestamp']).toUtc();
      } else if (newNotificationJson['sent_at'] != null) {
        newTimestamp = DateTime.parse(newNotificationJson['sent_at']).toUtc();
      } else {
        newTimestamp = DateTime.now().toUtc();
      }
    } catch (e) {
      newTimestamp = DateTime.now().toUtc();
    }

    // CRITICAL: Check if we've saved this ID recently with same timestamp
    final lastTimestamp = _lastSavedTimestamps[newId];
    if (lastTimestamp != null) {
      final lastTime =
          DateTime.fromMillisecondsSinceEpoch(lastTimestamp).toUtc();
      // If difference is less than 1 second, it's a duplicate
      if (newTimestamp.difference(lastTime).abs().inSeconds < 1) {
        debugPrint(
            '⚠️ [BG-Service] Duplicate detected for ID $newId, skipping');
        return;
      }
    }

    // CRITICAL FIX: Wait if another operation is writing
    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (waitCount >= 100) {
      debugPrint('⚠️ [BG-Service] Lock timeout - skipping save');
      return;
    }

    // Acquire lock
    _isWriting = true;
    _lockWaitCount++;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // Get existing list
      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

      // CRITICAL FIX: Remove ALL occurrences of this ID (aggressive deduplication)
      int removedCount = 0;
      list.removeWhere((item) {
        final itemId = item['id']?.toString();
        if (itemId == newId) {
          removedCount++;
          return true;
        }
        return false;
      });

      // Prepare final notification with proper timestamp
      final Map<String, dynamic> finalNotification =
          Map.from(newNotificationJson);
      finalNotification['id'] = newId;
      finalNotification['timestamp'] = newTimestamp.toIso8601String();

      // Insert at top
      list.insert(0, finalNotification);

      // Limit to 200
      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      // FINAL DEDUPLICATION PASS: Ensure no duplicates by ID
      final Map<String, dynamic> deduplicatedMap = {};
      for (var item in list) {
        final id = item['id']?.toString();
        if (id != null) {
          // If duplicate exists, keep the one with latest timestamp
          if (!deduplicatedMap.containsKey(id)) {
            deduplicatedMap[id] = item;
          } else {
            // Compare timestamps
            final existing = deduplicatedMap[id];
            final DateTime existingTime = _parseTimestamp(existing);
            final DateTime newTime = _parseTimestamp(item);
            if (newTime.isAfter(existingTime)) {
              deduplicatedMap[id] = item;
            }
          }
        }
      }
      list = deduplicatedMap.values.toList();

      // Sort by timestamp (newest first)
      list.sort((a, b) {
        final DateTime aTime = _parseTimestamp(a);
        final DateTime bTime = _parseTimestamp(b);
        return bTime.compareTo(aTime);
      });

      await prefs.setString(storageKey, jsonEncode(list));

      // Update last saved timestamp
      _lastSavedTimestamps[newId] = newTimestamp.millisecondsSinceEpoch;

      debugPrint(
          '💾 [BG-Service] Saved notification $newId (removed $removedCount duplicates)');
    } catch (e) {
      debugPrint('❌ [BG-Service] Save Failed: $e');
    } finally {
      _isWriting = false;
    }
  }

  // Helper to parse timestamp from map
  static DateTime _parseTimestamp(Map<String, dynamic> item) {
    try {
      if (item['timestamp'] != null) {
        return DateTime.parse(item['timestamp']).toUtc();
      } else if (item['sent_at'] != null) {
        return DateTime.parse(item['sent_at']).toUtc();
      }
    } catch (e) {
      // ignore
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // =========================================================
  // Save notification to server
  // =========================================================
  static Future<bool> saveNotificationToServer(
    Map<String, dynamic> notification,
  ) async {
    try {
      final uri = Uri.parse('$apiEndpoint?action=save_notification');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(notification),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // =========================================================
  // Mark as read on server
  // =========================================================
  static Future<bool> markAsRead(String id) async {
    try {
      final uri = Uri.parse('$apiEndpoint?action=mark_as_read');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id': id}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [NotificationService] markAsRead Error: $e');
      return false;
    }
  }

  // =========================================================
  // Delete notification on server
  // =========================================================
  static Future<bool> deleteNotification(String id) async {
    try {
      final uri = Uri.parse('$apiEndpoint?action=delete_notification');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id': id}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [NotificationService] deleteNotification Error: $e');
      return false;
    }
  }

  // =========================================================
  // Utility methods
  // =========================================================
  static bool get isWriting => _isWriting;
  static int get lockWaitCount => _lockWaitCount;

  // Clear timestamp cache (useful for testing)
  static void clearTimestampCache() {
    _lastSavedTimestamps.clear();
  }
}
