// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_database.dart';

// ignore_for_file: type=lint
class $NotificationsTableTable extends NotificationsTable
    with TableInfo<$NotificationsTableTable, NotificationsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _notificationIdMeta =
      const VerificationMeta('notificationId');
  @override
  late final GeneratedColumn<String> notificationId = GeneratedColumn<String>(
      'notification_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _dataJsonMeta =
      const VerificationMeta('dataJson');
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
      'data_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('general'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        notificationId,
        title,
        body,
        imageUrl,
        timestamp,
        dataJson,
        isRead,
        type,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notifications_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<NotificationsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('notification_id')) {
      context.handle(
          _notificationIdMeta,
          notificationId.isAcceptableOrUnknown(
              data['notification_id']!, _notificationIdMeta));
    } else if (isInserting) {
      context.missing(_notificationIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(_dataJsonMeta,
          dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta));
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      notificationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}notification_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url']),
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
      dataJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data_json'])!,
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $NotificationsTableTable createAlias(String alias) {
    return $NotificationsTableTable(attachedDatabase, alias);
  }
}

class NotificationsTableData extends DataClass
    implements Insertable<NotificationsTableData> {
  final int id;
  final String notificationId;
  final String title;
  final String body;
  final String? imageUrl;
  final DateTime timestamp;
  final String dataJson;
  final bool isRead;
  final String type;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NotificationsTableData(
      {required this.id,
      required this.notificationId,
      required this.title,
      required this.body,
      this.imageUrl,
      required this.timestamp,
      required this.dataJson,
      required this.isRead,
      required this.type,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['notification_id'] = Variable<String>(notificationId);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['data_json'] = Variable<String>(dataJson);
    map['is_read'] = Variable<bool>(isRead);
    map['type'] = Variable<String>(type);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NotificationsTableCompanion toCompanion(bool nullToAbsent) {
    return NotificationsTableCompanion(
      id: Value(id),
      notificationId: Value(notificationId),
      title: Value(title),
      body: Value(body),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      timestamp: Value(timestamp),
      dataJson: Value(dataJson),
      isRead: Value(isRead),
      type: Value(type),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NotificationsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationsTableData(
      id: serializer.fromJson<int>(json['id']),
      notificationId: serializer.fromJson<String>(json['notificationId']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      type: serializer.fromJson<String>(json['type']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'notificationId': serializer.toJson<String>(notificationId),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'dataJson': serializer.toJson<String>(dataJson),
      'isRead': serializer.toJson<bool>(isRead),
      'type': serializer.toJson<String>(type),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NotificationsTableData copyWith(
          {int? id,
          String? notificationId,
          String? title,
          String? body,
          Value<String?> imageUrl = const Value.absent(),
          DateTime? timestamp,
          String? dataJson,
          bool? isRead,
          String? type,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      NotificationsTableData(
        id: id ?? this.id,
        notificationId: notificationId ?? this.notificationId,
        title: title ?? this.title,
        body: body ?? this.body,
        imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
        timestamp: timestamp ?? this.timestamp,
        dataJson: dataJson ?? this.dataJson,
        isRead: isRead ?? this.isRead,
        type: type ?? this.type,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  NotificationsTableData copyWithCompanion(NotificationsTableCompanion data) {
    return NotificationsTableData(
      id: data.id.present ? data.id.value : this.id,
      notificationId: data.notificationId.present
          ? data.notificationId.value
          : this.notificationId,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      type: data.type.present ? data.type.value : this.type,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationsTableData(')
          ..write('id: $id, ')
          ..write('notificationId: $notificationId, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('timestamp: $timestamp, ')
          ..write('dataJson: $dataJson, ')
          ..write('isRead: $isRead, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, notificationId, title, body, imageUrl,
      timestamp, dataJson, isRead, type, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationsTableData &&
          other.id == this.id &&
          other.notificationId == this.notificationId &&
          other.title == this.title &&
          other.body == this.body &&
          other.imageUrl == this.imageUrl &&
          other.timestamp == this.timestamp &&
          other.dataJson == this.dataJson &&
          other.isRead == this.isRead &&
          other.type == this.type &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NotificationsTableCompanion
    extends UpdateCompanion<NotificationsTableData> {
  final Value<int> id;
  final Value<String> notificationId;
  final Value<String> title;
  final Value<String> body;
  final Value<String?> imageUrl;
  final Value<DateTime> timestamp;
  final Value<String> dataJson;
  final Value<bool> isRead;
  final Value<String> type;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const NotificationsTableCompanion({
    this.id = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.isRead = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  NotificationsTableCompanion.insert({
    this.id = const Value.absent(),
    required String notificationId,
    required String title,
    required String body,
    this.imageUrl = const Value.absent(),
    required DateTime timestamp,
    required String dataJson,
    this.isRead = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : notificationId = Value(notificationId),
        title = Value(title),
        body = Value(body),
        timestamp = Value(timestamp),
        dataJson = Value(dataJson);
  static Insertable<NotificationsTableData> custom({
    Expression<int>? id,
    Expression<String>? notificationId,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? imageUrl,
    Expression<DateTime>? timestamp,
    Expression<String>? dataJson,
    Expression<bool>? isRead,
    Expression<String>? type,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (notificationId != null) 'notification_id': notificationId,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (imageUrl != null) 'image_url': imageUrl,
      if (timestamp != null) 'timestamp': timestamp,
      if (dataJson != null) 'data_json': dataJson,
      if (isRead != null) 'is_read': isRead,
      if (type != null) 'type': type,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  NotificationsTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? notificationId,
      Value<String>? title,
      Value<String>? body,
      Value<String?>? imageUrl,
      Value<DateTime>? timestamp,
      Value<String>? dataJson,
      Value<bool>? isRead,
      Value<String>? type,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return NotificationsTableCompanion(
      id: id ?? this.id,
      notificationId: notificationId ?? this.notificationId,
      title: title ?? this.title,
      body: body ?? this.body,
      imageUrl: imageUrl ?? this.imageUrl,
      timestamp: timestamp ?? this.timestamp,
      dataJson: dataJson ?? this.dataJson,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (notificationId.present) {
      map['notification_id'] = Variable<String>(notificationId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationsTableCompanion(')
          ..write('id: $id, ')
          ..write('notificationId: $notificationId, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('timestamp: $timestamp, ')
          ..write('dataJson: $dataJson, ')
          ..write('isRead: $isRead, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$NotificationDatabase extends GeneratedDatabase {
  _$NotificationDatabase(QueryExecutor e) : super(e);
  $NotificationDatabaseManager get managers =>
      $NotificationDatabaseManager(this);
  late final $NotificationsTableTable notificationsTable =
      $NotificationsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [notificationsTable];
}

typedef $$NotificationsTableTableCreateCompanionBuilder
    = NotificationsTableCompanion Function({
  Value<int> id,
  required String notificationId,
  required String title,
  required String body,
  Value<String?> imageUrl,
  required DateTime timestamp,
  required String dataJson,
  Value<bool> isRead,
  Value<String> type,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$NotificationsTableTableUpdateCompanionBuilder
    = NotificationsTableCompanion Function({
  Value<int> id,
  Value<String> notificationId,
  Value<String> title,
  Value<String> body,
  Value<String?> imageUrl,
  Value<DateTime> timestamp,
  Value<String> dataJson,
  Value<bool> isRead,
  Value<String> type,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$NotificationsTableTableFilterComposer
    extends Composer<_$NotificationDatabase, $NotificationsTableTable> {
  $$NotificationsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notificationId => $composableBuilder(
      column: $table.notificationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dataJson => $composableBuilder(
      column: $table.dataJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$NotificationsTableTableOrderingComposer
    extends Composer<_$NotificationDatabase, $NotificationsTableTable> {
  $$NotificationsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notificationId => $composableBuilder(
      column: $table.notificationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dataJson => $composableBuilder(
      column: $table.dataJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$NotificationsTableTableAnnotationComposer
    extends Composer<_$NotificationDatabase, $NotificationsTableTable> {
  $$NotificationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get notificationId => $composableBuilder(
      column: $table.notificationId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NotificationsTableTableTableManager extends RootTableManager<
    _$NotificationDatabase,
    $NotificationsTableTable,
    NotificationsTableData,
    $$NotificationsTableTableFilterComposer,
    $$NotificationsTableTableOrderingComposer,
    $$NotificationsTableTableAnnotationComposer,
    $$NotificationsTableTableCreateCompanionBuilder,
    $$NotificationsTableTableUpdateCompanionBuilder,
    (
      NotificationsTableData,
      BaseReferences<_$NotificationDatabase, $NotificationsTableTable,
          NotificationsTableData>
    ),
    NotificationsTableData,
    PrefetchHooks Function()> {
  $$NotificationsTableTableTableManager(
      _$NotificationDatabase db, $NotificationsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotificationsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotificationsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> notificationId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> body = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
            Value<String> dataJson = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              NotificationsTableCompanion(
            id: id,
            notificationId: notificationId,
            title: title,
            body: body,
            imageUrl: imageUrl,
            timestamp: timestamp,
            dataJson: dataJson,
            isRead: isRead,
            type: type,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String notificationId,
            required String title,
            required String body,
            Value<String?> imageUrl = const Value.absent(),
            required DateTime timestamp,
            required String dataJson,
            Value<bool> isRead = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              NotificationsTableCompanion.insert(
            id: id,
            notificationId: notificationId,
            title: title,
            body: body,
            imageUrl: imageUrl,
            timestamp: timestamp,
            dataJson: dataJson,
            isRead: isRead,
            type: type,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$NotificationsTableTableProcessedTableManager = ProcessedTableManager<
    _$NotificationDatabase,
    $NotificationsTableTable,
    NotificationsTableData,
    $$NotificationsTableTableFilterComposer,
    $$NotificationsTableTableOrderingComposer,
    $$NotificationsTableTableAnnotationComposer,
    $$NotificationsTableTableCreateCompanionBuilder,
    $$NotificationsTableTableUpdateCompanionBuilder,
    (
      NotificationsTableData,
      BaseReferences<_$NotificationDatabase, $NotificationsTableTable,
          NotificationsTableData>
    ),
    NotificationsTableData,
    PrefetchHooks Function()>;

class $NotificationDatabaseManager {
  final _$NotificationDatabase _db;
  $NotificationDatabaseManager(this._db);
  $$NotificationsTableTableTableManager get notificationsTable =>
      $$NotificationsTableTableTableManager(_db, _db.notificationsTable);
}
