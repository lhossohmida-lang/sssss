import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'remote_store.dart';
import 'sync_profile.dart';

/// حصيلة جولة مزامنة.
class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.rejected = 0,
    this.pending = 0,
    this.error,
  });

  /// صفوف دُفعت إلى الخادم بنجاح.
  final int pushed;

  /// صفوف طُبّقت محلياً من الخادم.
  final int pulled;

  /// صفوف رفضها الخادم نهائياً (صلاحيات أو قيد) ورُكنت.
  final int rejected;

  /// عمليات ما زالت في الطابور تنتظر (عطل مؤقت).
  final int pending;

  /// آخر خطأ مؤقت إن وُجد (مثل انقطاع الإنترنت).
  final String? error;

  bool get isClean => error == null && rejected == 0 && pending == 0;
}

/// محرك المزامنة في الخلفية.
///
/// - **الدفع**: يرسل طابور العمليات بالترتيب. العطل المؤقت يوقف الجولة
///   ويعيد المحاولة لاحقاً بتأخير متزايد؛ الرفض النهائي يركن الصف وحده.
/// - **السحب**: يجلب ما تغيّر بعد آخر مؤشر لكل جدول ويطبّقه بقاعدة
///   «آخر تعديل يفوز» دون أن يعيده إلى الطابور.
class SyncEngine {
  SyncEngine(
    this.db,
    this.remote, {
    required this.tables,
    int Function()? clock,
    this.pushBatch = 100,
    this.pullBatch = 500,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch) {
    for (final table in db.allTables) {
      _tables[table.actualTableName] = table;
    }
  }

  final AppDatabase db;
  final RemoteStore remote;
  final List<SyncTable> tables;
  final int Function() _clock;
  final int pushBatch;
  final int pullBatch;

  final Map<String, TableInfo<Table, Object?>> _tables = {};

  /// عملية مرفوضة نهائياً تُركن بهذا الوقت حتى يعيدها المستخدم يدوياً.
  static const int parked = 9000000000000000;

  /// أقصى تأخير بين محاولتين.
  static const int _maxBackoffMs = 10 * 60 * 1000;

  /// جولة كاملة: دفع ثم سحب.
  Future<SyncReport> syncOnce() async {
    final push = await pushOutbox();
    if (push.error != null) return push;
    final pull = await pullAll();
    return SyncReport(
      pushed: push.pushed,
      pulled: pull.pulled,
      rejected: push.rejected,
      pending: push.pending,
      error: pull.error,
    );
  }

  // ---------------------------------------------------------------------------
  // الدفع
  // ---------------------------------------------------------------------------

  /// يدفع طابور العمليات إلى الخادم بالترتيب.
  Future<SyncReport> pushOutbox() async {
    var pushed = 0;
    var rejected = 0;
    String? error;
    final skipTables = {
      for (final table in tables)
        if (!table.push) table.local,
    };

    while (error == null) {
      final now = _clock();
      final batch =
          await (db.select(db.outbox)
                ..where((o) => o.nextAttemptAt.isSmallerOrEqualValue(now))
                ..orderBy([(o) => OrderingTerm(expression: o.seq)])
                ..limit(pushBatch))
              .get();
      if (batch.isEmpty) break;

      // مجموعات متتالية من نفس الجدول تُرسل في طلب واحد مع حفظ الترتيب.
      var index = 0;
      while (index < batch.length && error == null) {
        final table = batch[index].targetTable;
        final group = <OutboxRow>[];
        while (index < batch.length && batch[index].targetTable == table) {
          group.add(batch[index++]);
        }
        if (skipTables.contains(table) || !_tables.containsKey(table)) {
          await _remove(group);
          continue;
        }
        try {
          await _send(table, group);
          await _remove(group);
          pushed += group.length;
        } on RemoteException catch (e) {
          if (!e.permanent) {
            await _backoff(group, e.message);
            error = e.message;
          } else {
            // الخادم رفض المجموعة: تُرسل صفاً صفاً ليُركن المرفوض وحده.
            for (final row in group) {
              try {
                await _send(table, [row]);
                await _remove([row]);
                pushed++;
              } on RemoteException catch (single) {
                if (!single.permanent) {
                  await _backoff([row], single.message);
                  error = single.message;
                  break;
                }
                await _park(row, single.message);
                rejected++;
              }
            }
          }
        }
      }
    }
    return SyncReport(
      pushed: pushed,
      rejected: rejected,
      pending: await pendingCount(),
      error: error,
    );
  }

  /// عدد العمليات المنتظرة (دون المركونة).
  Future<int> pendingCount() => _count('next_attempt_at < $parked');

  /// عدد العمليات التي رفضها الخادم نهائياً.
  Future<int> rejectedCount() => _count('next_attempt_at >= $parked');

  /// يعيد العمليات المركونة إلى الطابور (بعد تصحيح الصلاحيات مثلاً).
  Future<void> retryRejected() => db.customUpdate(
    'UPDATE outbox SET next_attempt_at = 0, attempts = 0 '
    'WHERE next_attempt_at >= $parked',
    updates: {db.outbox},
  );

  Future<int> _count(String where) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM outbox WHERE $where',
          readsFrom: {db.outbox},
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<void> _send(String table, List<OutboxRow> rows) =>
      remote.upsert(table, [
        for (final row in rows)
          _toRemote(table, jsonDecode(row.payload) as Map<String, Object?>),
      ], insertOnly: SyncProfile.insertOnly.contains(table));

  Future<void> _remove(List<OutboxRow> rows) => db.customUpdate(
    'DELETE FROM outbox WHERE seq IN (${rows.map((r) => r.seq).join(', ')})',
    updates: {db.outbox},
    updateKind: UpdateKind.delete,
  );

  Future<void> _backoff(List<OutboxRow> rows, String message) async {
    final now = _clock();
    for (final row in rows) {
      final attempts = row.attempts + 1;
      final shift = attempts > 10 ? 10 : attempts;
      final delay = 5000 * (1 << (shift - 1));
      await (db.update(db.outbox)..where((o) => o.seq.equals(row.seq))).write(
        OutboxCompanion(
          attempts: Value(attempts),
          lastError: Value(message),
          nextAttemptAt: Value(
            now + (delay > _maxBackoffMs ? _maxBackoffMs : delay),
          ),
        ),
      );
    }
  }

  Future<void> _park(OutboxRow row, String message) =>
      (db.update(db.outbox)..where((o) => o.seq.equals(row.seq))).write(
        OutboxCompanion(
          attempts: Value(row.attempts + 1),
          lastError: Value(message),
          nextAttemptAt: const Value(parked),
        ),
      );

  // ---------------------------------------------------------------------------
  // السحب
  // ---------------------------------------------------------------------------

  /// يسحب ما تغيّر على الخادم لكل الجداول.
  Future<SyncReport> pullAll() async {
    var pulled = 0;
    try {
      for (final table in tables) {
        pulled += await _pullTable(table);
      }
    } on RemoteException catch (e) {
      return SyncReport(pulled: pulled, error: e.message);
    }
    return SyncReport(pulled: pulled);
  }

  Future<int> _pullTable(SyncTable table) async {
    var applied = 0;
    while (true) {
      final state = await (db.select(
        db.syncState,
      )..where((s) => s.targetTable.equals(table.local))).getSingleOrNull();
      final cursor = state?.lastPulledAt ?? 0;
      final rows = await remote.pull(
        table.remote,
        afterSyncedAt: cursor,
        limit: pullBatch,
      );
      if (rows.isEmpty) break;

      await db.transaction(() async {
        var newCursor = cursor;
        for (final row in rows) {
          if (await applyRemoteChange(table.local, row)) applied++;
          final synced = (row['synced_at'] as num?)?.toInt() ?? cursor;
          if (synced > newCursor) newCursor = synced;
        }
        await db
            .into(db.syncState)
            .insertOnConflictUpdate(
              SyncStateCompanion.insert(
                targetTable: table.local,
                lastPulledAt: Value(newCursor),
              ),
            );
      });
      if (rows.length < pullBatch) break;
    }
    return applied;
  }

  /// يطبّق صفاً قادماً من الخادم (سحب أو بث لحظي) بقاعدة «آخر تعديل يفوز».
  ///
  /// يعيد `true` إن كُتب الصف محلياً. لا يكتب في طابور الدفع ولا في سجل
  /// العمليات.
  Future<bool> applyRemoteChange(String table, Map<String, Object?> row) async {
    final info = _tables[table];
    if (info == null) return false;
    final keyColumns = [for (final c in info.$primaryKey) c.name];
    if (keyColumns.any((c) => row[c] == null)) return false;

    final where = keyColumns.map((c) => '"$c" = ?').join(' AND ');
    final keyValues = [for (final c in keyColumns) Variable<Object>(row[c]!)];
    final local = await db
        .customSelect(
          'SELECT updated_at FROM "$table" WHERE $where',
          variables: keyValues,
        )
        .getSingleOrNull();
    final remoteStamp = (row['updated_at'] as num?)?.toInt() ?? 0;
    if (local != null && local.read<int>('updated_at') > remoteStamp) {
      return false;
    }

    final columns = info.$columns;
    final names = columns.map((c) => '"${c.name}"').join(', ');
    final marks = List.filled(columns.length, '?').join(', ');
    await db.customInsert(
      'INSERT OR REPLACE INTO "$table" ($names) VALUES ($marks)',
      variables: [
        for (final column in columns) _toLocal(column, row[column.name]),
      ],
      updates: {info},
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // تحويل القيم بين SQLite و PostgreSQL
  // ---------------------------------------------------------------------------

  /// SQLite يخزّن المنطقي 0/1؛ الخادم يريده true/false.
  Map<String, Object?> _toRemote(String table, Map<String, Object?> payload) {
    final info = _tables[table]!;
    final result = <String, Object?>{};
    for (final column in info.$columns) {
      final value = payload[column.name];
      result[column.name] = column.type == DriftSqlType.bool && value is num
          ? value != 0
          : value;
    }
    return result;
  }

  static Variable<Object> _toLocal(
    GeneratedColumn<Object> column,
    Object? value,
  ) {
    if (value == null) {
      return switch (column.type) {
        DriftSqlType.string => const Variable<String>(null),
        DriftSqlType.double => const Variable<double>(null),
        _ => const Variable<int>(null),
      };
    }
    return switch (column.type) {
      DriftSqlType.bool => Variable<int>(
        value == true || (value is num && value != 0) ? 1 : 0,
      ),
      DriftSqlType.double => Variable<double>((value as num).toDouble()),
      DriftSqlType.int ||
      DriftSqlType.bigInt => Variable<int>((value as num).toInt()),
      _ => Variable<String>(value.toString()),
    };
  }
}
