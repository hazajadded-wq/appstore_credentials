import 'dart:convert';
import 'dart:async'; // Required for Completer and Future
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';

  // Lock to prevent concurrent writes causing duplication
  static bool _isWriting = false;

  // =========================================================
  // Get All Notifications From MySQL
  // =========================================================
  static Future<List<Map<String, dynamic>>> getAllNotifications(
      {int limit = 100}) async {
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
      debugPrint('❌ Network Error: $e');
    }

    return [];
  }

  // =========================================================
  // Save To Local Disk - The Updated Deduplication Mechanism
  // =========================================================
  static Future<void> saveToLocalDisk(
      Map<String, dynamic> newNotificationJson) async {
    // 1. Extract ID Uniformly
    final String? incomingId = newNotificationJson['id']?.toString() ??
        newNotificationJson['message_id']?.toString() ??
        newNotificationJson['data']?['id']?.toString();

    // 2. Validate Data
    final title = newNotificationJson['title']?.toString() ?? '';
    final body = newNotificationJson['body']?.toString() ?? '';

    if ((incomingId == null || incomingId.isEmpty) ||
        (title.isEmpty && body.isEmpty)) {
      debugPrint('🚫 [Service] Invalid notification data. Skipping.');
      return;
    }

    // 3. Lock Mechanism
    int retry = 0;
    while (_isWriting) {
      await Future.delayed(const Duration(milliseconds: 50));
      retry++;
      if (retry > 40) return; // Timeout after 2 seconds
    }

    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Critical: Reload from disk to ensure freshness (avoids BG/FG conflict)
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);
      List<dynamic> currentList = jsonStr != null ? jsonDecode(jsonStr) : [];

      // 4. Strict Check: Does this ID already exist?
      bool alreadyExists = currentList.any((item) {
        String existingId = item['id']?.toString() ?? '';
        return existingId == incomingId;
      });

      if (alreadyExists) {
        debugPrint(
            '🚫 [Service] Notification ID $incomingId already exists. SKIPPING SAVE.');
        return; // Exit immediately without saving
      }

      // 5. Prepare Data
      final Map<String, dynamic> finalNotification =
          Map.from(newNotificationJson);
      finalNotification['id'] = incomingId; // Unify ID

      // Add timestamp if missing
      if (!finalNotification.containsKey('timestamp')) {
        finalNotification['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      }

      // Insert at top
      currentList.insert(0, finalNotification);

      // Limit to 200 items
      if (currentList.length > 200) {
        currentList = currentList.sublist(0, 200);
      }

      // 6. Final Save
      await prefs.setString(storageKey, jsonEncode(currentList));
      debugPrint('💾 [Service] Saved successfully: $incomingId');
    } catch (e) {
      debugPrint('❌ [Service] Save Failed: $e');
    } finally {
      _isWriting = false; // Release lock
    }
  }

  // =========================================================
  // Get Local Notifications
  // =========================================================
  static Future<List<Map<String, dynamic>>> getLocalNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Reload is necessary to read what BG Isolate wrote
      await prefs.reload();
      final jsonStr = prefs.getString(storageKey);

      if (jsonStr == null) return [];
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      debugPrint('❌ Error parsing local notifications: $e');
      return [];
    }
  }

  // =========================================================
  // Delete Notification
  // =========================================================
  static Future<bool> deleteNotification(String id) async {
    while (_isWriting) await Future.delayed(const Duration(milliseconds: 50));
    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final jsonStr = prefs.getString(storageKey);

      if (jsonStr == null) return false;

      List<dynamic> list = jsonDecode(jsonStr);
      int initialLength = list.length;

      list.removeWhere((item) => item['id']?.toString() == id);

      if (list.length < initialLength) {
        await prefs.setString(storageKey, jsonEncode(list));
        debugPrint('🗑️ Deleted notification: $id');
        return true;
      }
      return false;
    } catch (e) {
      return false;
    } finally {
      _isWriting = false;
    }
  }

  // =========================================================
  // Clear All
  // =========================================================
  static Future<void> clearAllNotifications() async {
    while (_isWriting) await Future.delayed(const Duration(milliseconds: 50));
    _isWriting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } finally {
      _isWriting = false;
    }
  }

  static bool get isWriting => _isWriting;
}

