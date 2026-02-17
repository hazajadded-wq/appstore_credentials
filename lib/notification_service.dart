import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NotificationService - Client for PHP/MySQL notifications API.
/// مع تحسينات قوية لمنع التكرار
class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';

  static bool _isWriting = false;
  static int _lockWaitCount = 0;

  // تتبع الإشعارات المحفوظة
  static final Map<String, int> _lastSavedTimestamps = {};
  static final Set<String> _savedInSession = {};
  static final Set<String> _processedIds = {};

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
  // Save to Local Disk - مع منع التكرار نهائياً
  // =========================================================
  static Future<void> saveToLocalDisk(
      Map<String, dynamic> newNotificationJson) async {
    // التحقق من صحة البيانات
    final title = newNotificationJson['title']?.toString() ?? '';
    final body = newNotificationJson['body']?.toString() ?? '';
    if (title.isEmpty || (title == 'إشعار جديد' && body.isEmpty)) {
      debugPrint('⚠️ [Service] Skipping empty notification');
      return;
    }

    // الحصول على المعرف الفريد
    final String newId = newNotificationJson['id']?.toString() ??
        newNotificationJson['message_id']?.toString() ??
        'notif_${DateTime.now().millisecondsSinceEpoch}';

    // التحقق من المعالجة المسبقة
    if (_processedIds.contains(newId)) {
      debugPrint(
          '⚠️ [Service] Notification $newId already processed, skipping');
      return;
    }

    if (_savedInSession.contains(newId)) {
      debugPrint(
          '⚠️ [Service] Notification $newId already saved in session, skipping');
      return;
    }

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

    // التحقق من التكرار بناءً على الوقت
    final lastTimestamp = _lastSavedTimestamps[newId];
    if (lastTimestamp != null) {
      final lastTime =
          DateTime.fromMillisecondsSinceEpoch(lastTimestamp).toUtc();
      if (newTimestamp.difference(lastTime).abs().inSeconds < 3) {
        debugPrint(
            '⚠️ [Service] Time-based duplicate detected for ID $newId, skipping');
        return;
      }
    }

    // انتظار القفل
    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (waitCount >= 100) {
      debugPrint('⚠️ [Service] Lock timeout - skipping save');
      return;
    }

    _isWriting = true;
    _lockWaitCount++;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // قراءة القائمة الحالية
      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

      // التحقق مرة أخرى من التكرار في القائمة الحالية
      bool alreadyExists = list.any((item) {
        final itemId = item['id']?.toString();
        return itemId == newId;
      });

      if (alreadyExists) {
        debugPrint(
            '⚠️ [Service] Notification $newId already exists in storage, skipping');
        _processedIds.add(newId);
        _savedInSession.add(newId);
        return;
      }

      // إعداد الإشعار النهائي
      final Map<String, dynamic> finalNotification =
          Map.from(newNotificationJson);
      finalNotification['id'] = newId;
      finalNotification['timestamp'] = newTimestamp.toIso8601String();

      // إدراج في البداية
      list.insert(0, finalNotification);

      // الحد إلى 200
      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      // حفظ في SharedPreferences
      await prefs.setString(storageKey, jsonEncode(list));

      // تحديث التتبع
      _lastSavedTimestamps[newId] = newTimestamp.millisecondsSinceEpoch;
      _savedInSession.add(newId);
      _processedIds.add(newId);

      debugPrint('💾 [Service] Saved notification $newId successfully');
    } catch (e) {
      debugPrint('❌ [Service] Save Failed: $e');
    } finally {
      _isWriting = false;
    }
  }

  // =========================================================
  // Utility methods
  // =========================================================
  static bool get isWriting => _isWriting;
  static int get lockWaitCount => _lockWaitCount;

  // مسح التتبع
  static void clearTimestampCache() {
    _lastSavedTimestamps.clear();
    _savedInSession.clear();
    _processedIds.clear();
  }
}
