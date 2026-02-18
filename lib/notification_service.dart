import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String baseUrl = 'https://lpggaspro.org/scgfs_notifications';
  static const String apiEndpoint = '$baseUrl/notifications_api.php';
  static const String storageKey = 'stored_notifications_final';

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
  // ✅ Save To Local Disk - مُصحّح مع دعم associatedIds والمطابقة الذكية
  // =========================================================
  static Future<void> saveToLocalDisk(Map<String, dynamic> newNotificationJson,
      {bool fromClick = false}) async {
    // ❌ لا نحفظ أبداً إذا كان من الضغط
    if (fromClick) {
      debugPrint('🚫 [Service] Skipping save from click event');
      return;
    }

    final title = newNotificationJson['title']?.toString() ?? '';
    final body = newNotificationJson['body']?.toString() ?? '';

    if (title.isEmpty && body.isEmpty) {
      debugPrint('⚠️ [Service] Empty notification skipped');
      return;
    }

    // ✅ جمع كل المعرفات الممكنة من الإشعار الوارد
    final Set<String> incomingIds = {};

    final String? mainId = newNotificationJson['id']?.toString();
    final String? messageId = newNotificationJson['message_id']?.toString();

    if (mainId != null && mainId.isNotEmpty) incomingIds.add(mainId);
    if (messageId != null && messageId.isNotEmpty) incomingIds.add(messageId);

    // ✅ إضافة associatedIds إذا كانت موجودة
    if (newNotificationJson['associatedIds'] != null) {
      final List<dynamic> assocList = newNotificationJson['associatedIds'] is String
          ? jsonDecode(newNotificationJson['associatedIds'])
          : newNotificationJson['associatedIds'];
      for (var id in assocList) {
        if (id != null && id.toString().isNotEmpty) {
          incomingIds.add(id.toString());
        }
      }
    }

    if (incomingIds.isEmpty) {
      debugPrint('🚫 [Service] No valid ID found - skipping save');
      return;
    }

    // ✅ ID رئيسي
    final String primaryId = mainId ?? incomingIds.first;

    // ✅ انتظار القفل
    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      waitCount++;
    }

    if (waitCount >= 100) {
      debugPrint('⚠️ [Service] Lock timeout - skipping save');
      return;
    }

    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final jsonStr = prefs.getString(storageKey);

      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

      // ✅ المطابقة الذكية: بحث بالمعرفات + المحتوى
      int existingIndex = -1;
      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        final String itemId = item['id']?.toString() ?? '';

        // ✅ 1. مطابقة بالمعرفات
        bool idMatch = false;

        // تحقق من ID الرئيسي
        if (incomingIds.contains(itemId)) {
          idMatch = true;
        }

        // تحقق من associatedIds المخزنة
        if (!idMatch && item['associatedIds'] != null) {
          try {
            final List<dynamic> storedAssocIds = item['associatedIds'] is String
                ? jsonDecode(item['associatedIds'])
                : item['associatedIds'];
            final Set<String> storedIdSet =
                storedAssocIds.map((e) => e.toString()).toSet();
            if (storedIdSet.intersection(incomingIds).isNotEmpty) {
              idMatch = true;
            }
          } catch (e) {
            // ignore parsing errors
          }
        }

        // تحقق من message_id المخزن
        if (!idMatch) {
          final String? storedMsgId = item['message_id']?.toString();
          if (storedMsgId != null && incomingIds.contains(storedMsgId)) {
            idMatch = true;
          }
        }

        // ✅ 2. مطابقة بالمحتوى + التوقيت القريب
        if (!idMatch) {
          final String itemTitle = item['title']?.toString() ?? '';
          final String itemBody = item['body']?.toString() ?? '';

          if (title.isNotEmpty &&
              title == itemTitle &&
              body == itemBody) {
            // تحقق من التوقيت القريب (60 ثانية)
            try {
              DateTime? itemTime;
              if (item['timestamp'] != null) {
                if (item['timestamp'] is int) {
                  itemTime =
                      DateTime.fromMillisecondsSinceEpoch(item['timestamp']);
                } else {
                  itemTime = DateTime.parse(item['timestamp'].toString());
                }
              }

              DateTime? newTime;
              if (newNotificationJson['timestamp'] != null) {
                if (newNotificationJson['timestamp'] is int) {
                  newTime = DateTime.fromMillisecondsSinceEpoch(
                      newNotificationJson['timestamp']);
                } else {
                  newTime = DateTime.parse(
                      newNotificationJson['timestamp'].toString());
                }
              }

              if (itemTime != null && newTime != null) {
                if (itemTime.difference(newTime).inSeconds.abs() < 60) {
                  idMatch = true;
                }
              }
            } catch (e) {
              // ignore time parsing errors
            }
          }
        }

        if (idMatch) {
          existingIndex = i;
          break;
        }
      }

      if (existingIndex != -1) {
        // ✅ موجود مسبقاً - دمج المعرفات فقط
        final existing = list[existingIndex];

        Set<String> mergedIds = {...incomingIds};
        if (existing['associatedIds'] != null) {
          try {
            final List<dynamic> existingAssocIds =
                existing['associatedIds'] is String
                    ? jsonDecode(existing['associatedIds'])
                    : existing['associatedIds'];
            mergedIds.addAll(existingAssocIds.map((e) => e.toString()));
          } catch (e) {
            // ignore
          }
        }
        final existingId = existing['id']?.toString();
        if (existingId != null && existingId.isNotEmpty) {
          mergedIds.add(existingId);
        }

        list[existingIndex]['associatedIds'] = mergedIds.toList();

        await prefs.setString(storageKey, jsonEncode(list));
        debugPrint(
            '🔄 [Service] Merged IDs for existing notification: $primaryId');
        return;
      }

      // ✅ إشعار جديد - إضافة
      final Map<String, dynamic> finalNotification =
          Map<String, dynamic>.from(newNotificationJson);

      finalNotification['id'] = primaryId;
      finalNotification['associatedIds'] = incomingIds.toList();

      // إضافة timestamp إذا لم يكن موجوداً
      if (!finalNotification.containsKey('timestamp') ||
          finalNotification['timestamp'] == null) {
        finalNotification['timestamp'] =
            DateTime.now().millisecondsSinceEpoch;
      }

      // إدراج في البداية (الأحدث أولاً)
      list.insert(0, finalNotification);

      // الحد الأقصى 200 إشعار
      if (list.length > 200) {
        list = list.sublist(0, 200);
      }

      // حفظ في SharedPreferences
      await prefs.setString(storageKey, jsonEncode(list));

      debugPrint('💾 [Service] Saved new notification: $primaryId');
      debugPrint('📊 [Service] Total notifications: ${list.length}');
    } catch (e) {
      debugPrint('❌ [Service] Save Failed: $e');
    } finally {
      _isWriting = false;
    }
  }

  // =========================================================
  // Get Local Notifications
  // =========================================================
  static Future<List<Map<String, dynamic>>> getLocalNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
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
  // Delete Notification by ID - ✅ مُحسّن مع associatedIds
  // =========================================================
  static Future<bool> deleteNotification(String id) async {
    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      waitCount++;
    }

    if (waitCount >= 100) {
      debugPrint('⚠️ [Service] Lock timeout on delete');
      return false;
    }

    _isWriting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final jsonStr = prefs.getString(storageKey);

      if (jsonStr == null) return false;

      List<dynamic> list = jsonDecode(jsonStr);
      int initialLength = list.length;

      // ✅ حذف بناءً على ID الرئيسي أو أي من associatedIds
      list.removeWhere((item) {
        if (item['id']?.toString() == id) return true;

        if (item['associatedIds'] != null) {
          try {
            final List<dynamic> assocIds = item['associatedIds'] is String
                ? jsonDecode(item['associatedIds'])
                : item['associatedIds'];
            return assocIds.any((assocId) => assocId.toString() == id);
          } catch (e) {
            // ignore
          }
        }
        return false;
      });

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
    int waitCount = 0;
    while (_isWriting && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      waitCount++;
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
  // Get Writing Status
  // =========================================================
  static bool get isWriting => _isWriting;
}
