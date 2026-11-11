import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

/// من يقوم بالعملية الحالية (يُسجَّل في سجل العمليات).
class Actor {
  const Actor({required this.userId, required this.userName});

  /// عمليات النظام التلقائية (التغييب عند نهاية الحصة، اكتمال الدورة...).
  static const Actor system = Actor(userId: 'system', userName: 'النظام');

  final String userId;
  final String userName;
}

/// نقطة الكتابة الوحيدة في القاعدة المحلية للجداول المزامَنة.
///
/// كل كتابة تتم في معاملة واحدة:
/// 1. تُحفظ في الجدول مع ختم `updated_at`.
/// 2. تُسجَّل في `audit_log` (قبل / بعد) إن كان الجدول مما يُدقَّق.
/// 3. تُضاف إلى `outbox` لتُدفع إلى الخادم في الخلفية.
class SyncWriter {
  SyncWriter(
    this.db, {
    required this.actor,
    int Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
       _idGenerator = idGenerator ?? const Uuid().v4;

  final AppDatabase db;

  /// يعيد صاحب العملية الحالية.
  final Actor Function() actor;
  final int Function() _clock;
  final String Function() _idGenerator;

  int _lastStamp = 0;

  /// جداول لا تُكتب في سجل العمليات (كثيرة الحركة أو تقنية).
  static const Set<String> unaudited = {
    'audit_log',
    'chat_messages',
    'chat_members',
    'notifications',
    'sms_queue',
  };

  /// معرّف UUID جديد.
  String newId() => _idGenerator();

  /// الوقت الحالي بالميلي ثانية، متزايد دائماً حتى داخل نفس الميلي ثانية،
  /// ليبقى «آخر تعديل يفوز» محسوماً.
  int now() {
    final current = _clock();
    _lastStamp = current > _lastStamp ? current : _lastStamp + 1;
    return _lastStamp;
  }

  /// يضيف السجل أو يحدّثه. [key] يحدد السجل (عادةً `{'id': ...}`).
  ///
  /// [action] يظهر في سجل العمليات؛ الافتراضي `create` أو `update`.
  Future<void> save<D>(
    TableInfo<Table, D> table,
    Insertable<D> row, {
    required Map<String, Object> key,
    String? action,
  }) {
    return db.transaction(() async {
      final name = table.actualTableName;
      final before = await _read(name, key);
      await db.into(table).insertOnConflictUpdate(row);
      final stamp = now();
      await _stamp(table, key, stamp, createdAt: before?['created_at']);
      final after = await _read(name, key);
      if (after == null) {
        throw StateError('السجل غير موجود بعد الحفظ في $name');
      }
      await _record(
        name,
        key,
        action ?? (before == null ? 'create' : 'update'),
        before,
        after,
        stamp,
      );
    });
  }

  /// حذف ناعم: يضع `deleted_at` ويُبقي السجل للسجل المالي والحضور.
  ///
  /// يعيد `false` إن لم يوجد السجل أو كان محذوفاً من قبل.
  Future<bool> softDelete(
    TableInfo<Table, Object?> table, {
    required Map<String, Object> key,
  }) {
    return db.transaction(() async {
      final name = table.actualTableName;
      final before = await _read(name, key);
      if (before == null || before['deleted_at'] != null) return false;
      final stamp = now();
      final where = _where(key);
      await db.customUpdate(
        'UPDATE "$name" SET deleted_at = ?, updated_at = ? WHERE ${where.sql}',
        variables: [
          Variable<int>(stamp),
          Variable<int>(stamp),
          ...where.variables,
        ],
        updates: {table},
      );
      final after = await _read(name, key);
      await _record(name, key, 'delete', before, after!, stamp);
      return true;
    });
  }

  Future<void> _stamp(
    TableInfo<Table, Object?> table,
    Map<String, Object> key,
    int stamp, {
    Object? createdAt,
  }) async {
    final name = table.actualTableName;
    final columns = table.columnsByName;
    final sets = <String>[];
    final variables = <Variable<Object>>[];
    if (columns.containsKey('updated_at')) {
      sets.add('updated_at = ?');
      variables.add(Variable<int>(stamp));
    }
    if (columns.containsKey('created_at')) {
      sets.add('created_at = ?');
      variables.add(Variable<int>(createdAt is int ? createdAt : stamp));
    }
    if (sets.isEmpty) return;
    final where = _where(key);
    await db.customUpdate(
      'UPDATE "$name" SET ${sets.join(', ')} WHERE ${where.sql}',
      variables: [...variables, ...where.variables],
      updates: {table},
    );
  }

  Future<void> _record(
    String table,
    Map<String, Object> key,
    String action,
    Map<String, Object?>? before,
    Map<String, Object?> after,
    int stamp,
  ) async {
    final rowId = _rowId(key);
    await _enqueue(table, rowId, after, stamp);
    if (unaudited.contains(table)) return;
    final who = actor();
    final entry = <String, Object?>{
      'id': newId(),
      'user_id': who.userId,
      'user_name': who.userName,
      'action': action,
      'entity': table,
      'entity_id': rowId,
      'before': before == null ? null : jsonEncode(before),
      'after': action == 'delete' ? null : jsonEncode(after),
      'created_at': stamp,
      'updated_at': stamp,
    };
    await db.customInsert(
      'INSERT INTO audit_log (id, user_id, user_name, action, entity, '
      'entity_id, "before", "after", created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        for (final value in entry.values)
          value == null
              ? const Variable<String>(null)
              : Variable<Object>(value),
      ],
      updates: {db.auditLog},
    );
    await _enqueue('audit_log', entry['id']! as String, entry, stamp);
  }

  /// يضع السجل في طابور الدفع. عملية معلّقة أقدم لنفس السجل تُستبدل،
  /// فيُرسل إلى الخادم آخر حالة فقط.
  Future<void> _enqueue(
    String table,
    String rowId,
    Map<String, Object?> payload,
    int stamp,
  ) async {
    await db.customUpdate(
      'DELETE FROM outbox WHERE target_table = ? AND row_id = ?',
      variables: [Variable<String>(table), Variable<String>(rowId)],
      updates: {db.outbox},
      updateKind: UpdateKind.delete,
    );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: table,
            rowId: rowId,
            payload: jsonEncode(payload),
            createdAt: stamp,
          ),
        );
  }

  Future<Map<String, Object?>?> _read(
    String table,
    Map<String, Object> key,
  ) async {
    final where = _where(key);
    final row = await db
        .customSelect(
          'SELECT * FROM "$table" WHERE ${where.sql}',
          variables: where.variables,
        )
        .getSingleOrNull();
    return row?.data;
  }

  static String _rowId(Map<String, Object> key) {
    if (key.length == 1) return key.values.single.toString();
    return jsonEncode(key);
  }

  static ({String sql, List<Variable<Object>> variables}) _where(
    Map<String, Object> key,
  ) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'مفتاح السجل فارغ');
    }
    return (
      sql: key.keys.map((column) => '"$column" = ?').join(' AND '),
      variables: [for (final value in key.values) Variable<Object>(value)],
    );
  }
}
