import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'notification_database.g.dart';

class NotificationsTable extends Table {
  TextColumn get notificationId => text()(); // Firebase message ID - unique
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get imageUrl => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get dataJson => text()(); // Store full data as JSON
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  TextColumn get type => text().withDefault(const Constant('general'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {notificationId};
}

@DriftDatabase(tables: [NotificationsTable])
class NotificationDatabase extends _$NotificationDatabase {
  NotificationDatabase._internal() : super(_openConnection());

  static final NotificationDatabase _instance = NotificationDatabase._internal();
  static NotificationDatabase get instance => _instance;

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'notifications_db',
      native: DriftNativeOptions(
        databasePath: () async => await _databasePath,
      ),
    );
  }

  static Future<String> get _databasePath async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return p.join(dbFolder.path, 'notifications.db');
  }

  // ============================================
  // CRUD OPERATIONS
  // ============================================

  Future<List<NotificationsTableData>> getAllNotifications({
    int limit = 200,
    String? type,
    bool? isRead,
  }) {
    var query = select(notificationsTable)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);

    if (type != null) {
      query = query..where((t) => t.type.equals(type));
    }

    if (isRead != null) {
      query = query..where((t) => t.isRead.equals(isRead));
    }

    return (query..limit(limit)).get();
  }

  Future<NotificationsTableData?> getNotificationById(String notificationId) {
    return (select(notificationsTable)
          ..where((t) => t.notificationId.equals(notificationId)))
        .getSingleOrNull();
  }

  Future<int> insertOrUpdateNotification(NotificationsTableCompanion notification) {
    return into(notificationsTable).insertOnConflictUpdate(notification);
  }

  Future<bool> markAsRead(String notificationId) {
    return (update(notificationsTable)
          ..where((t) => t.notificationId.equals(notificationId)))
        .write(NotificationsTableCompanion(
          isRead: Value(true),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rowsAffected) => rowsAffected > 0);
  }

  Future<int> deleteNotification(String notificationId) {
    return (delete(notificationsTable)
          ..where((t) => t.notificationId.equals(notificationId)))
        .go();
  }

  Future<int> deleteOldNotifications({int keepLast = 200}) {
    // Keep only the most recent notifications
    final subquery = selectOnly(notificationsTable)
      ..addColumns([notificationsTable.notificationId])
      ..orderBy([OrderingTerm.desc(notificationsTable.timestamp)])
      ..limit(keepLast);

    return (delete(notificationsTable)
          ..where((t) => t.notificationId.isNotInQuery(subquery)))
        .go();
  }

  Future<int> getUnreadCount() {
    final countQuery = selectOnly(notificationsTable)
      ..addColumns([countAll(filter: notificationsTable.isRead.equals(false))]);
    return countQuery.map((row) => row.read(countAll())!).getSingle();
  }

  Future<int> getTotalCount() {
    final countQuery = selectOnly(notificationsTable)
      ..addColumns([countAll()]);
    return countQuery.map((row) => row.read(countAll())!).getSingle();
  }

  Future<void> clearAll() {
    return delete(notificationsTable).go().then((_) {});
  }

  // ============================================
  // SYNC OPERATIONS - CRITICAL FIX
  // ============================================

  Future<List<String>> getAllNotificationIds() {
    final query = selectOnly(notificationsTable)
      ..addColumns([notificationsTable.notificationId]);
    return query.map((row) => row.read(notificationsTable.notificationId)!).get();
  }

  Future<List<NotificationsTableData>> getNotificationsAfter(DateTime timestamp) {
    return (select(notificationsTable)
          ..where((t) => t.timestamp.isBiggerThanValue(timestamp))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .get();
  }

  /// CRITICAL FIX: Preserve isRead status during sync
  Future<void> bulkInsertNotifications(List<NotificationsTableCompanion> notifications) async {
    await batch((batch) async {
      for (final notification in notifications) {
        // Check if notification already exists
        final notificationId = notification.notificationId.value;
        final existing = await getNotificationById(notificationId);
        
        if (existing != null) {
          // CRITICAL: Preserve isRead status for existing notifications
          final preservedNotification = notification.copyWith(
            isRead: Value(existing.isRead), // ← Keep local isRead status!
            updatedAt: Value(DateTime.now()),
          );
          batch.insert(
            notificationsTable, 
            preservedNotification,
            onConflict: DoUpdate((old) => preservedNotification),
          );
        } else {
          // New notification - use server data
          batch.insert(
            notificationsTable, 
            notification,
            onConflict: DoUpdate((old) => notification),
          );
        }
      }
    });
  }

  /// NEW: Smart insert that preserves isRead
  Future<void> insertNotificationPreservingReadStatus(NotificationsTableCompanion notification) async {
    final notificationId = notification.notificationId.value;
    final existing = await getNotificationById(notificationId);
    
    if (existing != null && existing.isRead) {
      // Preserve read status
      final preservedNotification = notification.copyWith(
        isRead: Value(true),
        updatedAt: Value(DateTime.now()),
      );
      await into(notificationsTable).insertOnConflictUpdate(preservedNotification);
    } else {
      // New or unread - use as is
      await into(notificationsTable).insertOnConflictUpdate(notification);
    }
  }
}

// ============================================
// DATA MODEL EXTENSION
// ============================================

extension NotificationDataExtension on NotificationsTableData {
  Map<String, dynamic> toJson() {
    return {
      'id': notificationId,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'data': jsonDecode(dataJson),
      'isRead': isRead,
      'type': type,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// CRITICAL FIX: Don't override isRead from server
  static NotificationsTableCompanion fromJson(Map<String, dynamic> json, {bool? preserveReadStatus}) {
    return NotificationsTableCompanion(
      notificationId: Value(json['id'].toString()),
      title: Value(json['title'] ?? ''),
      body: Value(json['body'] ?? ''),
      imageUrl: Value(json['imageUrl'] ?? json['image_url']),
      timestamp: Value(DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] ?? json['sent_at'] ?? DateTime.now().millisecondsSinceEpoch)),
      dataJson: Value(jsonEncode(json['data'] ?? {})),
      // CRITICAL FIX: Only set isRead for new notifications
      isRead: preserveReadStatus == true 
          ? Value.absent() // Don't update isRead
          : Value(false), // New notification = unread
      type: Value(json['type'] ?? 'general'),
      createdAt: Value(DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch)),
      updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(
          json['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch)),
    );
  }
}
