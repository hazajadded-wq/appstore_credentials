import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// ============================================
/// LOCAL DATABASE SERVICE - SQLite
/// Simple, fast, reliable local storage
/// ============================================
class LocalDatabaseService {
  static Database? _database;
  static const String _dbName = 'notifications.db';
  static const String _tableName = 'notifications';

  // ============================================
  // INITIALIZE DATABASE
  // ============================================
  static Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    print('📂 [LocalDB] Initializing database at: $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  // ============================================
  // CREATE TABLE
  // ============================================
  static Future<void> _onCreate(Database db, int version) async {
    print('📂 [LocalDB] Creating notifications table...');

    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        type TEXT,
        image_url TEXT,
        created_at INTEGER NOT NULL,
        is_read INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0,
        data TEXT
      )
    ''');

    print('✅ [LocalDB] Table created successfully');
  }

  // ============================================
  // INSERT NOTIFICATION
  // Auto-deduplicates by PRIMARY KEY
  // ============================================
  static Future<bool> insert(Map<String, dynamic> notification) async {
    try {
      final db = await database;

      final id = notification['id']?.toString() ?? '';
      if (id.isEmpty) {
        print('❌ [LocalDB] Cannot insert - missing id');
        return false;
      }

      // Check if exists
      final exists = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (exists.isNotEmpty) {
        print('⚠️ [LocalDB] Notification $id already exists - skipping');
        return false;
      }

      // Prepare data
      final data = {
        'id': id,
        'title': notification['title'] ?? '',
        'body': notification['body'] ?? '',
        'type': notification['type'] ?? 'general',
        'image_url':
            notification['imageUrl'] ?? notification['image_url'] ?? '',
        'created_at':
            notification['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'is_read': notification['isRead'] == true ? 1 : 0,
        'synced': notification['synced'] == true ? 1 : 0,
        'data': jsonEncode(notification['data'] ?? {}),
      };

      await db.insert(
        _tableName,
        data,
        conflictAlgorithm: ConflictAlgorithm.ignore, // Auto-deduplicate
      );

      print('✅ [LocalDB] Inserted notification: $id');
      return true;
    } catch (e) {
      print('❌ [LocalDB] Insert error: $e');
      return false;
    }
  }

  // ============================================
  // GET ALL NOTIFICATIONS
  // Sorted by created_at DESC
  // ============================================
  static Future<List<Map<String, dynamic>>> getAll({int limit = 200}) async {
    try {
      final db = await database;

      final results = await db.query(
        _tableName,
        orderBy: 'created_at DESC',
        limit: limit,
      );

      print('📂 [LocalDB] Retrieved ${results.length} notifications');

      // Convert back to app format
      return results.map((row) {
        return {
          'id': row['id'],
          'title': row['title'],
          'body': row['body'],
          'type': row['type'],
          'imageUrl': row['image_url'],
          'timestamp': row['created_at'],
          'isRead': row['is_read'] == 1,
          'synced': row['synced'] == 1,
          'data': row['data'] != null ? jsonDecode(row['data'] as String) : {},
        };
      }).toList();
    } catch (e) {
      print('❌ [LocalDB] GetAll error: $e');
      return [];
    }
  }

  // ============================================
  // CHECK IF EXISTS
  // ============================================
  static Future<bool> exists(String id) async {
    try {
      final db = await database;

      final results = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      return results.isNotEmpty;
    } catch (e) {
      print('❌ [LocalDB] Exists error: $e');
      return false;
    }
  }

  // ============================================
  // MARK AS READ
  // ============================================
  static Future<bool> markAsRead(String id) async {
    try {
      final db = await database;

      await db.update(
        _tableName,
        {'is_read': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      print('✅ [LocalDB] Marked as read: $id');
      return true;
    } catch (e) {
      print('❌ [LocalDB] MarkAsRead error: $e');
      return false;
    }
  }

  // ============================================
  // MARK AS SYNCED
  // ============================================
  static Future<bool> markAsSynced(String id) async {
    try {
      final db = await database;

      await db.update(
        _tableName,
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      return true;
    } catch (e) {
      print('❌ [LocalDB] MarkAsSynced error: $e');
      return false;
    }
  }

  // ============================================
  // GET UNSYNCED
  // For queue system
  // ============================================
  static Future<List<Map<String, dynamic>>> getUnsynced() async {
    try {
      final db = await database;

      final results = await db.query(
        _tableName,
        where: 'synced = ?',
        whereArgs: [0],
      );

      return results.map((row) {
        return {
          'id': row['id'],
          'title': row['title'],
          'body': row['body'],
          'type': row['type'],
          'imageUrl': row['image_url'],
          'timestamp': row['created_at'],
          'data': row['data'] != null ? jsonDecode(row['data'] as String) : {},
        };
      }).toList();
    } catch (e) {
      print('❌ [LocalDB] GetUnsynced error: $e');
      return [];
    }
  }

  // ============================================
  // DELETE NOTIFICATION
  // ============================================
  static Future<bool> delete(String id) async {
    try {
      final db = await database;

      await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      print('✅ [LocalDB] Deleted notification: $id');
      return true;
    } catch (e) {
      print('❌ [LocalDB] Delete error: $e');
      return false;
    }
  }

  // ============================================
  // CLEAR ALL
  // ============================================
  static Future<bool> clearAll() async {
    try {
      final db = await database;

      await db.delete(_tableName);

      print('✅ [LocalDB] Cleared all notifications');
      return true;
    } catch (e) {
      print('❌ [LocalDB] ClearAll error: $e');
      return false;
    }
  }

  // ============================================
  // GET COUNT
  // ============================================
  static Future<int> getCount() async {
    try {
      final db = await database;

      final result =
          await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      final count = Sqflite.firstIntValue(result) ?? 0;

      return count;
    } catch (e) {
      print('❌ [LocalDB] GetCount error: $e');
      return 0;
    }
  }

  // ============================================
  // GET UNREAD COUNT
  // ============================================
  static Future<int> getUnreadCount() async {
    try {
      final db = await database;

      final result = await db.rawQuery(
          'SELECT COUNT(*) as count FROM $_tableName WHERE is_read = 0');
      final count = Sqflite.firstIntValue(result) ?? 0;

      return count;
    } catch (e) {
      print('❌ [LocalDB] GetUnreadCount error: $e');
      return 0;
    }
  }
}
