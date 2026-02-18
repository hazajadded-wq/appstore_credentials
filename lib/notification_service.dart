import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';

  static bool _isWriting = false;
  static final Set<String> _processedIds = {};
  static final Set<String> _savedInSession = {};
  static final Set<String> _clickedIds = {}; // NEW: Track clicked notifications

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
  // ✅ FIXED: Save To Local Disk with Click Detection
  // =========================================================
  static Future<void> saveToLocalDisk(
    Map<String, dynamic> newNotificationJson, {
    bool fromClick = false,
  }) async {
    // 🚫 CRITICAL: Never save if from click event
    if (fromClick) {
      debugPrint(
          '🚫 [Service] Skipping save - notification was clicked, not received');
      return;
    }

    final title = newNotificationJson['title']?.toString() ?? '';
    final body = newNotificationJson['body']?.toString() ?? '';

    if (title.isEmpty && body.isEmpty) {
      debugPrint('⚠️ [Service] Empty notification skipped');
      return;
    }

    // ✅ Extract ID from server only
    final String? incomingId = newNotificationJson['id']?.toString() ??
        newNotificationJson['message_id']?.toString();

    if (incomingId == null || incomingId.isEmpty) {
      debugPrint('🚫 [Service] No valid ID found - skipping save');
      return;
    }

    final String newId = incomingId;

    // ✅ Check if this ID was from a click event
    if (_clickedIds.contains(newId)) {
      debugPrint(
          '🚫 [Service] This notification was clicked - not saving again: $newId');
      return;
    }

    // ✅ Prevent duplicate processing in session
    if (_processedIds.contains(newId)) {
      debugPrint('🚫 [Service] Already processed in session: $newId');
      return;
    }

    if (_savedInSession.contains(newId)) {
      debugPrint('🚫 [Service] Already saved in session: $newId');
      return;
    }

    // ✅ Wait for write lock
    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      waitCount++;
    }

    if (waitCount >= 100) {
      debugPrint('⚠️ [Service] Write lock timeout');
      return;
    }

    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

      // 🔥 Check for existing notification
      bool alreadyExists = list.any((item) => item['id']?.toString() == newId);

      if (alreadyExists) {
        debugPrint('🚫 [Service] Duplicate detected in storage: $newId');
        _processedIds.add(newId);
        _savedInSession.add(newId);
        return;
      }

      // ✅ Prepare notification for save
      final Map<String, dynamic> finalNotification =
          Map.from(newNotificationJson);

      finalNotification['id'] = newId;

      // Add timestamp if not present
      if (!finalNotification.containsKey('timestamp')) {
        finalNotification['timestamp'] =
            DateTime.now().toUtc().toIso8601String();
      }

      // Add message_id if present
      if (newNotificationJson['message_id'] != null) {
        finalNotification['message_id'] = newNotificationJson['message_id'];
      }

      // Insert at beginning (newest first)
      list.insert(0, finalNotification);

      // Keep only 200 notifications
      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      // Save to SharedPreferences
      await prefs.setString(storageKey, jsonEncode(list));

      // Update tracking
      _processedIds.add(newId);
      _savedInSession.add(newId);

      debugPrint('💾 [Service] Saved successfully: $newId');
      debugPrint('📊 [Service] Total notifications: ${list.length}');
    } catch (e) {
      debugPrint('❌ [Service] Save Failed: $e');
    } finally {
      _isWriting = false;
    }
  }

  // =========================================================
  // NEW: Mark notification as clicked (prevent future saves)
  // =========================================================
  static void markAsClicked(String id) {
    _clickedIds.add(id);
    debugPrint('🖱️ [Service] Marked as clicked: $id');
  }

  // =========================================================
  // Get Local Notifications
  // =========================================================
  static Future<List<Map<String, dynamic>>> getLocalNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(storageKey);

    if (jsonStr == null) return [];

    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      debugPrint('❌ [Service] Error parsing local notifications: $e');
      return [];
    }
  }

  // =========================================================
  // Delete Notification by ID
  // =========================================================
  static Future<bool> deleteNotification(String id) async {
    while (_isWriting) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(storageKey);

      if (jsonStr == null) return false;

      List<dynamic> list = jsonDecode(jsonStr);
      int initialLength = list.length;

      list.removeWhere((item) => item['id']?.toString() == id);

      if (list.length < initialLength) {
        await prefs.setString(storageKey, jsonEncode(list));
        debugPrint('🗑️ [Service] Deleted notification: $id');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ [Service] Delete Failed: $e');
      return false;
    } finally {
      _isWriting = false;
    }
  }

  // =========================================================
  // Clear All Notifications
  // =========================================================
  static Future<void> clearAllNotifications() async {
    while (_isWriting) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      debugPrint('🗑️ [Service] All notifications cleared');
    } catch (e) {
      debugPrint('❌ [Service] Clear Failed: $e');
    } finally {
      _isWriting = false;
    }
  }

  // =========================================================
  // Clear Session Cache
  // =========================================================
  static void clearSessionCache() {
    _processedIds.clear();
    _savedInSession.clear();
    _clickedIds.clear();
    debugPrint('🧹 [Service] Session cache cleared');
  }

  // =========================================================
  // Get Writing Status
  // =========================================================
  static bool get isWriting => _isWriting;
}
