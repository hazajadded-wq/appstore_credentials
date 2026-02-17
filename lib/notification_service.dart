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

  // تتبع الإشعارات المحفوظة في الجلسة الحالية
  static final Set<String> _savedInSession = {};

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
  // Save To Local Disk - ✅ الحفظ فقط عند الاستقبال وليس عند الضغط
  // =========================================================
  static Future<void> saveToLocalDisk(Map<String, dynamic> newNotificationJson,
      {bool fromClick = false}) async {
    // ❌ لا نحفظ أبداً إذا كان من الضغط
    if (fromClick) {
      debugPrint('🚫 Skipping save from click event');
      return;
    }

    final title = newNotificationJson['title']?.toString() ?? '';
    final body = newNotificationJson['body']?.toString() ?? '';

    if (title.isEmpty && body.isEmpty) {
      debugPrint('⚠️ Empty notification skipped');
      return;
    }

    // ✅ نستخدم message_id دائماً كمُعرّف موحّد
    final String? incomingId = newNotificationJson['message_id']?.toString() ??
        newNotificationJson['firebase_message_id']?.toString() ??
        newNotificationJson['id']?.toString();

    if (incomingId == null || incomingId.isEmpty) {
      debugPrint('🚫 No valid ID found - skipping save');
      return;
    }

    final String newId = incomingId;

    // ✅ منع التكرار في نفس الجلسة
    if (_processedIds.contains(newId)) {
      debugPrint('🚫 Already processed in session: $newId');
      return;
    }

    if (_savedInSession.contains(newId)) {
      debugPrint('🚫 Already saved in session: $newId');
      return;
    }

    // ✅ انتظار القفل
    while (_isWriting) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(storageKey);

      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

      // 🔥 منع التكرار نهائياً في التخزين
      bool alreadyExists = list.any((item) {
        final id = item['message_id']?.toString() ??
            item['firebase_message_id']?.toString() ??
            item['id']?.toString();
        return id == newId;
      });

      if (alreadyExists) {
        debugPrint('🚫 Duplicate detected in storage: $newId');
        _processedIds.add(newId);
        _savedInSession.add(newId);
        return;
      }

      // ✅ تجهيز الإشعار للحفظ
      final Map<String, dynamic> finalNotification =
          Map<String, dynamic>.from(newNotificationJson);

      // توحيد المعرف داخل JSON
      finalNotification['id'] = newId;
      if (!(finalNotification.containsKey('message_id') ||
          finalNotification.containsKey('firebase_message_id'))) {
        finalNotification['message_id'] = newId;
      }

      // توحيد الـ timestamp إلى milliseconds
      final rawTs = finalNotification['timestamp'];
      if (rawTs == null) {
        finalNotification['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      } else if (rawTs is String) {
        try {
          finalNotification['timestamp'] =
              DateTime.parse(rawTs).millisecondsSinceEpoch;
        } catch (_) {
          finalNotification['timestamp'] =
              DateTime.now().millisecondsSinceEpoch;
        }
      } else if (rawTs is! int) {
        finalNotification['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      }

      // إدراج في البداية (الأحدث أولاً)
      list.insert(0, finalNotification);

      // الحد الأقصى 200 إشعار
      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      // حفظ في SharedPreferences
      await prefs.setString(storageKey, jsonEncode(list));

      // تحديث التتبع
      _processedIds.add(newId);
      _savedInSession.add(newId);

      debugPrint('💾 Saved successfully: $newId');
      debugPrint('📊 Total notifications: ${list.length}');
    } catch (e) {
      debugPrint('❌ Save Failed: $e');
    } finally {
      _isWriting = false;
    }
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
      debugPrint('❌ Error parsing local notifications: $e');
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

      list.removeWhere((item) {
        final key = item['message_id']?.toString() ??
            item['firebase_message_id']?.toString() ??
            item['id']?.toString();
        return key == id;
      });

      if (list.length < initialLength) {
        await prefs.setString(storageKey, jsonEncode(list));
        debugPrint('🗑️ Deleted notification: $id');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Delete Failed: $e');
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
      debugPrint('🗑️ All notifications cleared');
    } catch (e) {
      debugPrint('❌ Clear Failed: $e');
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
    debugPrint('🧹 Session cache cleared');
  }

  // =========================================================
  // Get Writing Status
  // =========================================================
  static bool get isWriting => _isWriting;
}
