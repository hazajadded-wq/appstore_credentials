import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NotificationService - Client for PHP/MySQL notifications API.
class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';

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
  // =========================================================
  static Future<void> saveToLocalDisk(
    Map<String, dynamic> newNotificationJson,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // FORCE RELOAD: Ensure we are seeing the latest data on disk
      await prefs.reload();

      // Get existing list
      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

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

      await prefs.setString(storageKey, jsonEncode(list));
      debugPrint('💾 [BG-Service] Saved notification $newId to disk.');
    } catch (e) {
      debugPrint('❌ [BG-Service] Save Failed: $e');
    }
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
  // Mark as read
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
      return false;
    }
  }

  // =========================================================
  // Delete notification
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
      return false;
    }
  }
}
