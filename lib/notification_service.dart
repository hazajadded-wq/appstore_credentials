import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NotificationService - Client for PHP/MySQL notifications API.
class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';

  // CRITICAL: Shared lock to prevent concurrent SharedPreferences access
  static bool _isWriting = false;
  static int _lockWaitCount = 0;

  // =========================================================
  // Get all notifications from MySQL
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
      debugPrint('❌ [NotificationService] Network Error: $e');
    }

    return [];
  }

  // =========================================================
  // CRITICAL: Save to Local Disk (Safe for Background)
  // WITH PROPER LOCKING
  // =========================================================
  static Future<void> saveToLocalDisk(
      Map<String, dynamic> newNotificationJson) async {
    // CRITICAL FIX: Wait if another operation is writing
    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      // Max 10 second wait
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

      // FORCE RELOAD: Ensure we are seeing the latest data on disk
      await prefs.reload();

      // Get existing list
      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

      // Add new item to TOP of list
      final newId = newNotificationJson['id'].toString();

      // CRITICAL FIX: More aggressive deduplication
      // Remove ALL occurrences of this ID (in case of corruption)
      list.removeWhere((item) => item['id']?.toString() == newId);

      // Insert at top
      list.insert(0, newNotificationJson);

      // Limit to 200
      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      // CRITICAL FIX: Final deduplication pass before saving
      final Map<String, dynamic> deduplicatedMap = {};
      for (var item in list) {
        final id = item['id']?.toString();
        if (id != null && !deduplicatedMap.containsKey(id)) {
          deduplicatedMap[id] = item;
        }
      }
      list = deduplicatedMap.values.toList();

      await prefs.setString(storageKey, jsonEncode(list));
      debugPrint(
          '💾 [BG-Service] Saved notification $newId to disk (waited $waitCount cycles, total locks: $_lockWaitCount)');
    } catch (e) {
      debugPrint('❌ [BG-Service] Save Failed: $e');
    } finally {
      // CRITICAL: Always release lock
      _isWriting = false;
    }
  }

  // =========================================================
  // Utility method to check lock status (for debugging)
  // =========================================================
  static bool get isWriting => _isWriting;
  static int get lockWaitCount => _lockWaitCount;
}
