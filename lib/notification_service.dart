import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mysql1/mysql1.dart';

/// NotificationService - DIRECT MySQL Connection
/// ⚠️ WARNING: Database credentials are in app code (SECURITY RISK)
/// 
/// This version connects directly to MySQL database
/// For production, use API version instead (notification_service_api.dart)
class NotificationService {
  // ============================================
  // ⚠️ SECURITY WARNING: Database Credentials
  // These will be visible in decompiled app
  // ============================================
  static const String _dbHost = 'localhost'; // أو عنوان IP السيرفر
  static const String _dbPort = '3306';
  static const String _dbName = 'u623061738_scgfs_notifica';
  static const String _dbUser = 'u623061738_scgfs_notifica';
  static const String _dbPassword = 'Ila171988'; // ⚠️ EXPOSED IN APP
  
  static const String storageKey = 'stored_notifications_final_v2';
  static bool _isInitialized = false;

  // ============================================
  // COMPATIBILITY: Check internet connection
  // ============================================
  static Future<bool> hasInternetConnection() async {
    try {
      // In MySQL direct mode, we need internet to connect to database
      // Try to connect to see if we have internet
      final conn = await _getConnection();
      if (conn != null) {
        await conn.close();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ [NotificationService] No internet connection');
      return false;
    }
  }

  // ============================================
  // Initialize service
  // ============================================
  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('🚀 [NotificationService] Initialized - DIRECT MySQL Mode');
    debugPrint('⚠️ [WARNING] Database credentials are in app code');
  }

  // ============================================
  // Create MySQL Connection
  // ============================================
  static Future<MySqlConnection?> _getConnection() async {
    try {
      final settings = ConnectionSettings(
        host: _dbHost,
        port: int.parse(_dbPort),
        user: _dbUser,
        password: _dbPassword,
        db: _dbName,
        timeout: Duration(seconds: 10),
      );

      final conn = await MySqlConnection.connect(settings);
      debugPrint('✅ [MySQL] Connected to database');
      return conn;
    } catch (e) {
      debugPrint('❌ [MySQL] Connection error: $e');
      return null;
    }
  }

  // ============================================
  // DIRECT DATABASE FETCH: Get all notifications
  // ============================================
  static Future<List<Map<String, dynamic>>> getAllNotifications({
    int limit = 100,
    String? targetValue,
    String? employeeId,
  }) async {
    MySqlConnection? conn;
    
    try {
      debugPrint('📡 [MySQL] Fetching notifications from database...');
      
      conn = await _getConnection();
      if (conn == null) {
        debugPrint('❌ [MySQL] Failed to connect');
        return [];
      }

      // Build query with optional filtering
      String query = '''
        SELECT 
          id,
          firebase_message_id,
          title,
          body,
          image_url,
          type,
          priority,
          target_type,
          target_value,
          data_payload,
          sent_at,
          success_count,
          failure_count,
          is_hidden
        FROM notification_logs
        WHERE is_hidden = 0
      ''';

      List<dynamic> params = [];

      // Add department filter if provided
      if (targetValue != null && targetValue.isNotEmpty) {
        query += " AND (target_value = ? OR target_value = 'all_employees')";
        params.add(targetValue);
      }

      query += " ORDER BY sent_at DESC LIMIT ?";
      params.add(limit);

      debugPrint('🔍 [MySQL] Query: $query');
      debugPrint('🔍 [MySQL] Params: $params');

      // Execute query
      var results = await conn.query(query, params);

      List<Map<String, dynamic>> notifications = [];

      for (var row in results) {
        notifications.add({
          'id': row['id'].toString(),
          'message_id': row['firebase_message_id'] ?? '',
          'title': row['title'] ?? '',
          'body': row['body'] ?? '',
          'image_url': row['image_url'] ?? '',
          'type': row['type'] ?? 'general',
          'priority': row['priority'] ?? 'normal',
          'target_type': row['target_type'] ?? 'all',
          'target_value': row['target_value'] ?? '',
          'data_payload': row['data_payload'] ?? '{}',
          'sent_at': row['sent_at'].toString(),
          'success_count': row['success_count'] ?? 0,
          'failure_count': row['failure_count'] ?? 0,
        });
      }

      debugPrint('✅ [MySQL] Fetched ${notifications.length} notifications');

      // Get read status if employee_id provided
      if (employeeId != null && employeeId.isNotEmpty && notifications.isNotEmpty) {
        await _addReadStatus(conn, notifications, employeeId);
      }

      // Save to local cache
      await _saveToLocal(notifications);

      return notifications;

    } catch (e, stackTrace) {
      debugPrint('❌ [MySQL] Fetch Error: $e');
      debugPrint('❌ [MySQL] StackTrace: $stackTrace');
      
      // Fallback to local cache
      return await getLocalNotifications();
      
    } finally {
      // Always close connection
      await conn?.close();
      debugPrint('🔌 [MySQL] Connection closed');
    }
  }

  // ============================================
  // Add read status for each notification
  // ============================================
  static Future<void> _addReadStatus(
    MySqlConnection conn,
    List<Map<String, dynamic>> notifications,
    String employeeId,
  ) async {
    try {
      if (notifications.isEmpty) return;

      // Get all notification IDs
      List<String> ids = notifications.map((n) => n['id'].toString()).toList();
      String placeholders = List.filled(ids.length, '?').join(',');

      String query = '''
        SELECT notification_id, is_read
        FROM notification_read_status
        WHERE employee_id = ? AND notification_id IN ($placeholders)
      ''';

      List<dynamic> params = [employeeId, ...ids];

      var results = await conn.query(query, params);

      // Create map of read statuses
      Map<String, bool> readStatus = {};
      for (var row in results) {
        readStatus[row['notification_id'].toString()] = row['is_read'] == 1;
      }

      // Add read status to each notification
      for (var notif in notifications) {
        notif['is_read'] = readStatus[notif['id']] ?? false;
      }

      debugPrint('✅ [MySQL] Added read status for ${readStatus.length} notifications');

    } catch (e) {
      debugPrint('❌ [MySQL] Read status error: $e');
    }
  }

  // ============================================
  // DIRECT DATABASE UPDATE: Mark as read
  // COMPATIBILITY: employeeId is optional (defaults to 'system')
  // ============================================
  static Future<void> markAsRead(String id, [String? employeeId]) async {
    MySqlConnection? conn;
    
    // Use 'system' if no employeeId provided (backward compatibility)
    final empId = employeeId ?? 'system';
    
    try {
      debugPrint('📝 [MySQL] Marking notification $id as read for $empId');
      
      conn = await _getConnection();
      if (conn == null) {
        debugPrint('❌ [MySQL] Failed to connect');
        return;
      }

      String query = '''
        INSERT INTO notification_read_status (notification_id, employee_id, is_read, read_at)
        VALUES (?, ?, 1, NOW())
        ON DUPLICATE KEY UPDATE
          is_read = 1,
          read_at = NOW()
      ''';

      await conn.query(query, [id, empId]);

      debugPrint('✅ [MySQL] Marked $id as read for $empId');

      // Update local cache
      await _updateLocalReadStatus(id, true);

    } catch (e) {
      debugPrint('❌ [MySQL] Mark as read error: $e');
    } finally {
      await conn?.close();
    }
  }

  // ============================================
  // DIRECT DATABASE UPDATE: Mark all as read
  // COMPATIBILITY: both parameters optional
  // ============================================
  static Future<void> markAllAsRead([String? employeeId, String? targetValue]) async {
    MySqlConnection? conn;
    
    // Use 'system' if no employeeId provided (backward compatibility)
    final empId = employeeId ?? 'system';
    
    try {
      debugPrint('📝 [MySQL] Marking all as read for $empId');
      
      conn = await _getConnection();
      if (conn == null) {
        debugPrint('❌ [MySQL] Failed to connect');
        return;
      }

      // First, get all unread notification IDs
      String selectQuery = '''
        SELECT nl.id
        FROM notification_logs nl
        LEFT JOIN notification_read_status nrs 
          ON nl.id = nrs.notification_id AND nrs.employee_id = ?
        WHERE nl.is_hidden = 0
          AND (nrs.is_read IS NULL OR nrs.is_read = 0)
      ''';

      List<dynamic> selectParams = [empId];

      if (targetValue != null && targetValue.isNotEmpty) {
        selectQuery += " AND (nl.target_value = ? OR nl.target_value = 'all_employees')";
        selectParams.add(targetValue);
      }

      var results = await conn.query(selectQuery, selectParams);

      if (results.isEmpty) {
        debugPrint('ℹ️ [MySQL] No unread notifications to mark');
        return;
      }

      // Mark all as read
      List<String> ids = results.map((row) => row['id'].toString()).toList();
      
      for (String notifId in ids) {
        await conn.query('''
          INSERT INTO notification_read_status (notification_id, employee_id, is_read, read_at)
          VALUES (?, ?, 1, NOW())
          ON DUPLICATE KEY UPDATE is_read = 1, read_at = NOW()
        ''', [notifId, empId]);
      }

      debugPrint('✅ [MySQL] Marked ${ids.length} notifications as read');

    } catch (e) {
      debugPrint('❌ [MySQL] Mark all as read error: $e');
    } finally {
      await conn?.close();
    }
  }

  // ============================================
  // Get unread count
  // COMPATIBILITY: both parameters optional
  // ============================================
  static Future<int> getUnreadCount([String? employeeId, String? targetValue]) async {
    MySqlConnection? conn;
    
    // Use 'system' if no employeeId provided
    final empId = employeeId ?? 'system';
    
    try {
      conn = await _getConnection();
      if (conn == null) return 0;

      String query = '''
        SELECT COUNT(*) as unread
        FROM notification_logs nl
        LEFT JOIN notification_read_status nrs 
          ON nl.id = nrs.notification_id AND nrs.employee_id = ?
        WHERE nl.is_hidden = 0
          AND (nrs.is_read IS NULL OR nrs.is_read = 0)
      ''';

      List<dynamic> params = [empId];

      if (targetValue != null && targetValue.isNotEmpty) {
        query += " AND (nl.target_value = ? OR nl.target_value = 'all_employees')";
        params.add(targetValue);
      }

      var results = await conn.query(query, params);
      
      if (results.isNotEmpty) {
        return results.first['unread'] ?? 0;
      }

      return 0;

    } catch (e) {
      debugPrint('❌ [MySQL] Unread count error: $e');
      return 0;
    } finally {
      await conn?.close();
    }
  }

  // ============================================
  // Save to local cache
  // ============================================
  static Future<void> _saveToLocal(List<Map<String, dynamic>> notifications) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(notifications));
      debugPrint('💾 [Local] Saved ${notifications.length} notifications to cache');
    } catch (e) {
      debugPrint('❌ [Local] Save error: $e');
    }
  }

  // ============================================
  // Get from local cache
  // ============================================
  static Future<List<Map<String, dynamic>>> getLocalNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final notifications = list.map((e) => Map<String, dynamic>.from(e)).toList();
        debugPrint('📂 [Local] Loaded ${notifications.length} from cache');
        return notifications;
      }
    } catch (e) {
      debugPrint('❌ [Local] Load failed: $e');
    }

    return [];
  }

  // ============================================
  // Update local read status
  // ============================================
  static Future<void> _updateLocalReadStatus(String id, bool isRead) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null) {
        List<dynamic> list = jsonDecode(jsonStr);
        
        for (var item in list) {
          if (item['id'].toString() == id) {
            item['is_read'] = isRead;
            break;
          }
        }

        await prefs.setString(storageKey, jsonEncode(list));
        debugPrint('✅ [Local] Updated read status for $id');
      }
    } catch (e) {
      debugPrint('❌ [Local] Update read status error: $e');
    }
  }

  // ============================================
  // Delete notification
  // ============================================
  static Future<void> deleteNotification(String id) async {
    MySqlConnection? conn;
    
    try {
      conn = await _getConnection();
      if (conn == null) return;

      await conn.query('UPDATE notification_logs SET is_hidden = 1 WHERE id = ?', [id]);
      debugPrint('🗑️ [MySQL] Deleted notification $id');

      // Update local cache
      final notifications = await getLocalNotifications();
      notifications.removeWhere((n) => n['id'].toString() == id);
      await _saveToLocal(notifications);

    } catch (e) {
      debugPrint('❌ [MySQL] Delete error: $e');
    } finally {
      await conn?.close();
    }
  }

  // ============================================
  // COMPATIBILITY: saveToLocalDisk
  // Called by background handler in main.dart
  // In MySQL direct mode, we save to cache only
  // ============================================
  static Future<void> saveToLocalDisk(Map<String, dynamic> newNotificationJson) async {
    try {
      debugPrint('💾 [NotificationService] Saving to local disk: ${newNotificationJson['id']}');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final jsonStr = prefs.getString(storageKey);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];

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
      debugPrint('✅ [NotificationService] Saved to local disk');

    } catch (e) {
      debugPrint('❌ [NotificationService] Save to disk error: $e');
    }
  }

  // ============================================
  // COMPATIBILITY: saveNotificationToServer
  // In MySQL direct mode, we don't need this
  // But keeping for compatibility with main.dart
  // ============================================
  static Future<bool> saveNotificationToServer(Map<String, dynamic> notification) async {
    try {
      debugPrint('ℹ️ [NotificationService] saveNotificationToServer called');
      debugPrint('ℹ️ [MySQL Direct Mode] This is not needed - notifications already in database');
      
      // In MySQL direct mode, we don't save to server
      // The admin panel already saved it to database
      // We just fetch from database directly
      
      return true;
    } catch (e) {
      debugPrint('❌ [NotificationService] Save to server error: $e');
      return false;
    }
  }

  // ============================================
  // COMPATIBILITY: syncPendingToServer
  // In MySQL direct mode, we don't need this
  // ============================================
  static Future<void> syncPendingToServer() async {
    debugPrint('ℹ️ [NotificationService] syncPendingToServer called');
    debugPrint('ℹ️ [MySQL Direct Mode] No pending sync needed');
    // In MySQL direct mode, everything is already in database
    // No need to sync
  }

  // ============================================
  // Clear all notifications
  // ============================================
  static Future<void> clearAllNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      debugPrint('✅ [Local] Cleared all notifications');
    } catch (e) {
      debugPrint('❌ [Local] Clear failed: $e');
    }
  }
}
