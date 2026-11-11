import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  late AppDatabase db;
  late SyncWriter writer;
  late int time;
  late int ids;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    time = 1000;
    ids = 0;
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'u1', userName: 'المدير'),
      clock: () => time,
      idGenerator: () => 'id-${++ids}',
    );
  });

  tearDown(() => db.close());

  RoomsCompanion room(String name, {int capacity = 20}) =>
      RoomsCompanion.insert(
        id: 'r1',
        createdAt: 0,
        updatedAt: 0,
        name: name,
        capacity: Value(capacity),
      );

  Future<void> saveRoom(String name, {int capacity = 20}) => writer.save(
    db.rooms,
    room(name, capacity: capacity),
    key: const {'id': 'r1'},
  );

  test('الإضافة تختم الوقت وتسجّل في السجل وفي طابور الدفع', () async {
    await saveRoom('القاعة 1');

    final row = await db.select(db.rooms).getSingle();
    expect(row.createdAt, 1000);
    expect(row.updatedAt, 1000);

    final audit = await db.select(db.auditLog).getSingle();
    expect(audit.action, 'create');
    expect(audit.entity, 'rooms');
    expect(audit.entityId, 'r1');
    expect(audit.userId, 'u1');
    expect(audit.userName, 'المدير');
    expect(audit.before, isNull);
    expect((jsonDecode(audit.after!) as Map)['name'], 'القاعة 1');

    final outbox = await db.select(db.outbox).get();
    expect(outbox.map((o) => o.targetTable), ['rooms', 'audit_log']);
    final payload = jsonDecode(outbox.first.payload) as Map;
    expect(payload['id'], 'r1');
    expect(payload['updated_at'], 1000);
    expect(payload['deleted_at'], isNull);
  });

  test('التعديل يحفظ وقت الإنشاء ويسجّل الحالة قبل وبعد', () async {
    await saveRoom('القاعة 1');
    time = 5000;
    await saveRoom('القاعة الكبرى', capacity: 40);

    final row = await db.select(db.rooms).getSingle();
    expect(row.createdAt, 1000);
    expect(row.updatedAt, 5000);
    expect(row.capacity, 40);

    final audits = await (db.select(
      db.auditLog,
    )..orderBy([(a) => OrderingTerm(expression: a.createdAt)])).get();
    expect(audits.map((a) => a.action), ['create', 'update']);
    expect((jsonDecode(audits.last.before!) as Map)['capacity'], 20);
    expect((jsonDecode(audits.last.after!) as Map)['capacity'], 40);
  });

  test('طابور الدفع يحتفظ بآخر حالة فقط لكل سجل', () async {
    await saveRoom('القاعة 1');
    time = 5000;
    await saveRoom('القاعة 2');

    final pending = await (db.select(
      db.outbox,
    )..where((o) => o.targetTable.equals('rooms'))).get();
    expect(pending, hasLength(1));
    expect((jsonDecode(pending.single.payload) as Map)['name'], 'القاعة 2');
  });

  test('الوقت متزايد حتى داخل نفس الميلي ثانية', () async {
    final a = writer.now();
    final b = writer.now();
    final c = writer.now();
    expect(b, greaterThan(a));
    expect(c, greaterThan(b));
  });

  test('الحذف الناعم يُبقي السجل ويسجّل العملية', () async {
    await saveRoom('القاعة 1');
    time = 7000;

    expect(await writer.softDelete(db.rooms, key: const {'id': 'r1'}), isTrue);
    final row = await db.select(db.rooms).getSingle();
    expect(row.deletedAt, 7000);
    expect(row.updatedAt, 7000);

    final last =
        await (db.select(db.auditLog)
              ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
              ..limit(1))
            .getSingle();
    expect(last.action, 'delete');
    expect(last.before, isNotNull);
    expect(last.after, isNull);

    expect(
      await writer.softDelete(db.rooms, key: const {'id': 'r1'}),
      isFalse,
      reason: 'المحذوف لا يُحذف مرتين',
    );
    expect(
      await writer.softDelete(db.rooms, key: const {'id': 'missing'}),
      isFalse,
    );
  });

  test('الجداول كثيرة الحركة تُزامَن دون سجل عمليات', () async {
    await writer.save(
      db.smsQueue,
      SmsQueueCompanion.insert(
        id: 'm1',
        createdAt: 0,
        updatedAt: 0,
        phone: '+213550123456',
        message: 'مرحبا',
      ),
      key: const {'id': 'm1'},
    );
    expect(await db.select(db.auditLog).get(), isEmpty);
    final outbox = await db.select(db.outbox).getSingle();
    expect(outbox.targetTable, 'sms_queue');
  });

  test('الجداول ذات المفتاح غير `id` تُحفظ بمفتاحها', () async {
    await writer.save(
      db.settings,
      SettingsCompanion.insert(
        key: 'school_name',
        value: 'مدرسة النجاح',
        updatedAt: 0,
      ),
      key: const {'key': 'school_name'},
    );
    final row = await db.select(db.settings).getSingle();
    expect(row.updatedAt, 1000);
    final outbox = await (db.select(
      db.outbox,
    )..where((o) => o.targetTable.equals('settings'))).getSingle();
    expect(outbox.rowId, 'school_name');
  });

  test('فشل الحفظ يتراجع عن كل شيء', () async {
    Future<void> student(String id) => writer.save(
      db.students,
      StudentsCompanion.insert(
        id: id,
        createdAt: 0,
        updatedAt: 0,
        firstName: 'أحمد',
        lastName: 'بن علي',
        parentPhone: '0550123456',
        qrCode: 'S-AAAAAAAAAA',
      ),
      key: {'id': id},
    );
    await student('s1');
    final auditBefore = (await db.select(db.auditLog).get()).length;
    final outboxBefore = (await db.select(db.outbox).get()).length;

    await expectLater(student('s2'), throwsA(isA<Exception>()));

    expect(await db.select(db.students).get(), hasLength(1));
    expect(await db.select(db.auditLog).get(), hasLength(auditBefore));
    expect(await db.select(db.outbox).get(), hasLength(outboxBefore));
  });

  test('عمليات النظام تُنسب إلى «النظام»', () async {
    final system = SyncWriter(db, actor: () => Actor.system, clock: () => 1);
    await system.save(db.rooms, room('القاعة 1'), key: const {'id': 'r1'});
    final audit = await db.select(db.auditLog).getSingle();
    expect(audit.userId, 'system');
  });
}
