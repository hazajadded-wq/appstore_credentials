import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// NotificationService - Client for PHP/MySQL notifications API.
/// FIXED: With offline support and retry mechanism
class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';
  static const String pendingStorageKey =
      'pending_notifications'; // للإشعارات المعلقة

  static bool _isWriting = false;
  static int _lockWaitCount = 0;
  static final Map<String, int> _lastSavedTimestamps = {};

  // قائمة الإشعارات المعلقة (لم ترسل بعد لعدم وجود إنترنت)
  static bool _isRetrying = false;
  static Timer? _retryTimer;

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
  // التحقق من اتصال الإنترنت
  // =========================================================
  static Future<bool> hasInternetConnection() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // تحقق إضافي: محاولة الاتصال بالخادم
      final response = await http
          .get(
        Uri.parse('$apiEndpoint?action=test'),
      )
          .timeout(const Duration(seconds: 3), onTimeout: () {
        throw TimeoutException('Connection timeout');
      });

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ [Internet Check] No connection: $e');
      return false;
    }
  }

  // =========================================================
  // حفظ الإشعارات المعلقة (للحالات بدون إنترنت)
  // =========================================================
  static Future<void> savePendingNotification(
      Map<String, dynamic> notification) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(pendingStorageKey);
      List<dynamic> pending = jsonStr != null ? jsonDecode(jsonStr) : [];

      // تجنب التكرار في القائمة المعلقة
      final newId = notification['id']?.toString();
      pending.removeWhere((item) => item['id']?.toString() == newId);

      pending.insert(0, notification);

      // حد أقصى 50 إشعار معلق
      if (pending.length > 50) {
        pending = pending.sublist(0, 50);
      }

      await prefs.setString(pendingStorageKey, jsonEncode(pending));
      debugPrint('📦 [Pending] Saved pending notification: $newId');
    } catch (e) {
      debugPrint('❌ [Pending] Error saving pending: $e');
    }
  }

  // =========================================================
  // تحميل الإشعارات المعلقة
  // =========================================================
  static Future<List<Map<String, dynamic>>> loadPendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(pendingStorageKey);
      if (jsonStr != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
      }
    } catch (e) {
      debugPrint('❌ [Pending] Error loading pending: $e');
    }
    return [];
  }

  // =========================================================
  // مسح الإشعارات المعلقة بعد إرسالها
  // =========================================================
  static Future<void> clearPendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(pendingStorageKey);
      debugPrint('📦 [Pending] Cleared all pending notifications');
    } catch (e) {
      debugPrint('❌ [Pending] Error clearing pending: $e');
    }
  }

  // =========================================================
  // إعادة محاولة إرسال الإشعارات المعلقة
  // =========================================================
  static Future<void> retryPendingNotifications() async {
    if (_isRetrying) return;

    _isRetrying = true;

    try {
      final hasInternet = await hasInternetConnection();
      if (!hasInternet) {
        _isRetrying = false;
        return;
      }

      final pending = await loadPendingNotifications();
      if (pending.isEmpty) {
        _isRetrying = false;
        return;
      }

      debugPrint(
          '🔄 [Retry] Attempting to send ${pending.length} pending notifications');

      List<Map<String, dynamic>> failedToSend = [];

      for (var notification in pending) {
        try {
          // محاولة حفظ الإشعار في قاعدة البيانات
          await saveToMySQL(notification);
          debugPrint(
              '✅ [Retry] Successfully sent notification: ${notification['id']}');
        } catch (e) {
          debugPrint('❌ [Retry] Failed to send: ${notification['id']}');
          failedToSend.add(notification);
        }

        // تأخير صغير بين المحاولات
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (failedToSend.isEmpty) {
        await clearPendingNotifications();
      } else {
        // حفظ الإشعارات التي فشلت مرة أخرى
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(pendingStorageKey, jsonEncode(failedToSend));
      }
    } catch (e) {
      debugPrint('❌ [Retry] Error in retry process: $e');
    } finally {
      _isRetrying = false;
    }
  }

  // =========================================================
  // بدء مراقبة اتصال الإنترنت
  // =========================================================
  static void startConnectivityMonitoring() {
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
          if (result != ConnectivityResult.none) {
            debugPrint(
                '📡 [Connectivity] Internet connected - retrying pending notifications');
            // تأخير لمدة ثانيتين للتأكد من استقرار الاتصال
            _retryTimer?.cancel();
            _retryTimer = Timer(const Duration(seconds: 2), () {
              retryPendingNotifications();
            });
          }
        } as void Function(List<ConnectivityResult> event)?);
  }

  // =========================================================
  // حفظ الإشعار في MySQL (مع دعم عدم الاتصال)
  // =========================================================
  static Future<bool> saveToMySQL(Map<String, dynamic> notification) async {
    try {
      final response = await http
          .post(
            Uri.parse('$apiEndpoint?action=save_notification'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(notification),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('❌ [MySQL] Error saving to MySQL: $e');
    }
    return false;
  }

  // =========================================================
  // CRITICAL: Save to Local Disk (Safe for Background)
  // WITH PROPER LOCKING AND DEDUPLICATION
  // =========================================================
  static Future<void> saveToLocalDisk(
      Map<String, dynamic> newNotificationJson) async {
    final title = newNotificationJson['title']?.toString() ?? '';
    final body = newNotificationJson['body']?.toString() ?? '';
    if (title.isEmpty || (title == 'إشعار جديد' && body.isEmpty)) {
      debugPrint('⚠️ [BG-Service] Skipping empty notification');
      return;
    }

    final String newId = newNotificationJson['id']?.toString() ??
        newNotificationJson['message_id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

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

    await Future.delayed(const Duration(milliseconds: 100));

    final lastTimestamp = _lastSavedTimestamps[newId];
    if (lastTimestamp != null) {
      final lastTime =
          DateTime.fromMillisecondsSinceEpoch(lastTimestamp).toUtc();
      if (newTimestamp.difference(lastTime).abs().inSeconds < 3) {
        debugPrint(
            '⚠️ [BG-Service] Duplicate detected for ID $newId, skipping');
        return;
      }
    }

    // التحقق من وجود إنترنت
    final hasInternet = await hasInternetConnection();

    if (!hasInternet) {
      // لا يوجد إنترنت - حفظ في القائمة المعلقة
      debugPrint('📦 [BG-Service] No internet - saving to pending: $newId');
      await savePendingNotification(newNotificationJson);
      return;
    }

    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (waitCount >= 100) {
      debugPrint('⚠️ [BG-Service] Lock timeout - skipping save');
      return;
    }

    _isWriting = true;
    _lockWaitCount++;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

      bool contentDuplicate = false;
      for (var item in list) {
        final itemTitle = item['title']?.toString() ?? '';
        final itemBody = item['body']?.toString() ?? '';
        final DateTime itemTime = _parseTimestamp(item);

        if (itemTitle == title && itemBody == body) {
          final timeDiff = newTimestamp.difference(itemTime).abs();
          if (timeDiff.inSeconds < 10) {
            contentDuplicate = true;
            debugPrint('⚠️ [BG-Service] Content duplicate detected, skipping');
            break;
          }
        }
      }

      if (contentDuplicate) {
        return;
      }

      int removedCount = 0;
      list.removeWhere((item) {
        final itemId = item['id']?.toString();
        if (itemId == newId) {
          removedCount++;
          return true;
        }
        return false;
      });

      final Map<String, dynamic> finalNotification =
          Map.from(newNotificationJson);
      finalNotification['id'] = newId;
      finalNotification['timestamp'] = newTimestamp.toIso8601String();

      list.insert(0, finalNotification);

      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      final Map<String, dynamic> deduplicatedMap = {};
      for (var item in list) {
        final id = item['id']?.toString();
        if (id != null) {
          if (!deduplicatedMap.containsKey(id)) {
            deduplicatedMap[id] = item;
          } else {
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

      list.sort((a, b) {
        final DateTime aTime = _parseTimestamp(a);
        final DateTime bTime = _parseTimestamp(b);
        return bTime.compareTo(aTime);
      });

      await prefs.setString(storageKey, jsonEncode(list));

      // محاولة حفظ في MySQL إذا كان هناك إنترنت
      if (hasInternet) {
        unawaited(saveToMySQL(newNotificationJson));
      }

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
    } catch (e) {}
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // =========================================================
  // Utility methods
  // =========================================================
  static bool get isWriting => _isWriting;
  static int get lockWaitCount => _lockWaitCount;

  static void clearTimestampCache() {
    _lastSavedTimestamps.clear();
  }
}
