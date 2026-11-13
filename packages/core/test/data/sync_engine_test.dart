import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/src/data/remote/synced_tables.dart';

import '../support/fake_remote.dart';
import '../support/fixtures.dart';

void main() {
  late FakeRemote remote;
  late TestEnv a;
  late SyncEngine engineA;

  SyncEngine engineFor(
    TestEnv env, {
    UserRole role = UserRole.owner,
    int pullBatch = 500,
    int pushBatch = 100,
  }) => SyncEngine(
    env.db,
    remote,
    tables: SyncProfile.forRole(role),
    clock: () => env.time,
    pullBatch: pullBatch,
    pushBatch: pushBatch,
  );

  Future<void> saveRoom(
    TestEnv env,
    String id,
    String name, {
    int capacity = 20,
  }) => env.writer.save(
    env.db.rooms,
    RoomsCompanion.insert(
      id: id,
      createdAt: 0,
      updatedAt: 0,
      name: name,
      capacity: Value(capacity),
    ),
    key: {'id': id},
  );

  Future<RoomRow?> room(TestEnv env, String id) => (env.db.select(
    env.db.rooms,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  setUp(() {
    remote = FakeRemote();
    a = TestEnv();
    engineA = engineFor(a);
  });

  tearDown(() => a.close());

  group('الدفع', () {
    test('يرسل الطابور بالترتيب ويفرغه', () async {
      await saveRoom(a, 'r1', 'القاعة 1');
      await saveRoom(a, 'r2', 'القاعة 2');

      final report = await engineA.pushOutbox();

      expect(report.pushed, 4, reason: 'قاعتان وسجلا عمليات');
      expect(report.isClean, isTrue);
      expect(await a.db.select(a.db.outbox).get(), isEmpty);
      expect(remote.rows('rooms').map((r) => r['name']), [
        'القاعة 1',
        'القاعة 2',
      ]);
      expect(remote.rows('audit_log'), hasLength(2));
    });

    test('القيم المنطقية تُرسل true/false لا 0/1', () async {
      await a.writer.save(
        a.db.students,
        StudentsCompanion.insert(
          id: 's1',
          createdAt: 0,
          updatedAt: 0,
          firstName: 'أحمد',
          lastName: 'ب',
          parentPhone: '0550123456',
          qrCode: 'S-AAAAAAAAAA',
          usesTransport: const Value(true),
        ),
        key: const {'id': 's1'},
      );
      await engineA.pushOutbox();
      final sent = remote.row('students', 's1')!;
      expect(sent['uses_transport'], isTrue);
      expect(sent['transport_price'], 0);
      expect(sent['deleted_at'], isNull);
      expect(sent.containsKey('photo_url'), isTrue);
    });

    test('صفوف متتالية من نفس الجدول تُرسل في طلب واحد', () async {
      await a.db.batch((b) {
        for (var i = 0; i < 5; i++) {
          b.insert(
            a.db.outbox,
            OutboxCompanion.insert(
              targetTable: 'rooms',
              rowId: 'r$i',
              payload: jsonEncode({
                'id': 'r$i',
                'created_at': 1,
                'updated_at': 1,
                'deleted_at': null,
                'name': 'ق$i',
                'capacity': 5,
              }),
              createdAt: 1,
            ),
          );
        }
      });
      await engineA.pushOutbox();
      expect(remote.calls, ['upsert:rooms:5']);
    });

    test('انقطاع الإنترنت: الطابور يبقى ويُعاد لاحقاً بتأخير متزايد', () async {
      await saveRoom(a, 'r1', 'القاعة 1');
      remote.offline = true;

      final failed = await engineA.pushOutbox();
      expect(failed.pushed, 0);
      expect(failed.error, 'لا يوجد اتصال');
      expect(failed.pending, 2);
      final waiting = (await a.db.select(a.db.outbox).get()).first;
      expect(waiting.attempts, 1);
      expect(waiting.nextAttemptAt, a.time + 5000);
      expect(waiting.lastError, 'لا يوجد اتصال');

      remote.offline = false;
      expect(
        (await engineA.pushOutbox()).pushed,
        1,
        reason: 'الصف المؤجَّل لا يُعاد قبل وقته، وما بعده يمرّ',
      );

      a.time += 5000;
      final retried = await engineA.pushOutbox();
      expect(retried.pushed, 1);
      expect(retried.isClean, isTrue);
      expect(remote.rows('rooms'), hasLength(1));
    });

    test('التأخير يتضاعف ولا يتجاوز 10 دقائق', () async {
      await saveRoom(a, 'r1', 'القاعة 1');
      remote.offline = true;
      final delays = <int>[];
      for (var i = 0; i < 12; i++) {
        await engineA.pushOutbox();
        final row = (await a.db.select(a.db.outbox).get()).first;
        delays.add(row.nextAttemptAt - a.time);
        a.time = row.nextAttemptAt;
      }
      expect(delays.take(4), [5000, 10000, 20000, 40000]);
      expect(delays.last, 600000);
    });

    test('الصف المرفوض نهائياً يُركن وحده والباقي يمرّ', () async {
      await saveRoom(a, 'r1', 'مقبولة');
      await saveRoom(a, 'r2', 'ممنوعة');
      await saveRoom(a, 'r3', 'مقبولة أيضاً');
      // إزالة سجلات العمليات من الطابور لتبقى القاعات متتالية.
      await (a.db.delete(
        a.db.outbox,
      )..where((o) => o.targetTable.equals('audit_log'))).go();
      remote.reject = (table, row) =>
          row['name'] == 'ممنوعة' ? 'صلاحيات غير كافية' : null;

      final report = await engineA.pushOutbox();
      expect(report.pushed, 2);
      expect(report.rejected, 1);
      expect(report.pending, 0);
      expect(report.error, isNull);
      expect(remote.rows('rooms').map((r) => r['id']), ['r1', 'r3']);
      expect(await engineA.rejectedCount(), 1);
      final parkedRow = await a.db.select(a.db.outbox).getSingle();
      expect(parkedRow.rowId, 'r2');
      expect(parkedRow.lastError, 'صلاحيات غير كافية');

      expect(
        (await engineA.pushOutbox()).pushed,
        0,
        reason: 'المركون لا يُعاد',
      );

      remote.reject = null;
      await engineA.retryRejected();
      expect((await engineA.pushOutbox()).pushed, 1);
      expect(await engineA.rejectedCount(), 0);
    });

    test('سجل العمليات يُضاف فقط ولا يُستبدل', () async {
      await saveRoom(a, 'r1', 'القاعة 1');
      await engineA.pushOutbox();
      final first = remote.rows('audit_log').single;
      await a.db
          .into(a.db.outbox)
          .insert(
            OutboxCompanion.insert(
              targetTable: 'audit_log',
              rowId: first['id']! as String,
              payload: jsonEncode({
                ...first,
                'action': 'مزوَّر',
                'updated_at': 99,
              }),
              createdAt: 1,
            ),
          );
      await engineA.pushOutbox();
      expect(remote.rows('audit_log').single['action'], 'create');
    });

    test('دفع أكبر من حجم الدفعة يكتمل على مراحل', () async {
      final small = engineFor(a, pushBatch: 3);
      for (var i = 0; i < 4; i++) {
        await saveRoom(a, 'r$i', 'ق$i');
      }
      final report = await small.pushOutbox();
      expect(report.pushed, 8);
      expect(report.pending, 0);
    });
  });

  group('السحب', () {
    late TestEnv b;
    late SyncEngine engineB;

    setUp(() {
      b = TestEnv(idPrefix: 'b')..time = 1000;
      engineB = engineFor(b);
    });

    tearDown(() => b.close());

    test('جهاز ثانٍ يستلم ما دفعه الأول دون أن يعيده', () async {
      await saveRoom(a, 'r1', 'القاعة 1', capacity: 30);
      await engineA.syncOnce();

      final report = await engineB.syncOnce();
      expect(report.pulled, 2);
      final pulled = await room(b, 'r1');
      expect(pulled?.name, 'القاعة 1');
      expect(pulled?.capacity, 30);
      expect(await b.db.select(b.db.auditLog).get(), hasLength(1));
      expect(
        await b.db.select(b.db.outbox).get(),
        isEmpty,
        reason: 'المسحوب لا يدخل طابور الدفع',
      );

      remote.calls.clear();
      expect((await engineB.syncOnce()).pulled, 0, reason: 'المؤشر تقدّم');
    });

    test('القيم المنطقية والعشرية تُحوَّل عند السحب', () async {
      await remote.upsert('students', [
        {
          'id': 's1',
          'created_at': 1,
          'updated_at': 1,
          'deleted_at': null,
          'first_name': 'أحمد',
          'last_name': 'ب',
          'parent_phone': '0550123456',
          'uses_transport': true,
          'transport_price': 1500,
          'qr_code': 'S-AAAAAAAAAA',
        },
      ]);
      await remote.upsert('subjects', [
        {
          'id': 'sub',
          'created_at': 1,
          'updated_at': 1,
          'name': 'رياضيات',
          'monthly_price': 2000,
        },
      ]);
      await remote.upsert('teachers', [
        {
          'id': 't1',
          'created_at': 1,
          'updated_at': 1,
          'name': 'كريم',
          'phone': '0770000000',
          'email': 't1@school.local',
          'rate_per_student': 1000,
          'qr_code': 'T-AAAAAAAAAA',
        },
      ]);
      await remote.upsert('groups', [
        {
          'id': 'g1',
          'created_at': 1,
          'updated_at': 1,
          'number': 1,
          'subject_id': 'sub',
          'teacher_id': 't1',
          'sessions_per_cycle': 8,
          'current_cycle_number': 1,
        },
      ]);
      await remote.upsert('grades', [
        {
          'id': 'gr1',
          'created_at': 1,
          'updated_at': 1,
          'student_id': 's1',
          'group_id': 'g1',
          'title': 'فرض',
          'score': 15,
          'max_score': 20,
          'note': '',
          'date': '2026-11-14',
        },
      ]);
      await engineB.pullAll();

      final student = await b.db.select(b.db.students).getSingle();
      expect(student.usesTransport, isTrue);
      expect(student.transportPrice, 1500);
      expect(student.photoUrl, isNull);
      final grade = await b.db.select(b.db.grades).getSingle();
      expect(grade.score, 15.0);
    });

    test('السحب على دفعات حتى ينتهي', () async {
      for (var i = 0; i < 5; i++) {
        await saveRoom(a, 'r$i', 'ق$i');
      }
      await engineA.pushOutbox();
      final paged = engineFor(b, pullBatch: 2);
      await paged.pullAll();
      expect(await b.db.select(b.db.rooms).get(), hasLength(5));
      expect(
        remote.calls.where((c) => c == 'pull:rooms'),
        hasLength(3),
        reason: 'دفعتان كاملتان ثم دفعة ناقصة',
      );
    });

    test('آخر تعديل يفوز: الأحدث محلياً لا يُستبدل بالأقدم', () async {
      await saveRoom(a, 'r1', 'نسخة قديمة');
      await engineA.pushOutbox();

      b.time = 5000;
      await saveRoom(b, 'r1', 'نسخة أحدث محلياً');
      await engineB.pullAll();
      expect((await room(b, 'r1'))?.name, 'نسخة أحدث محلياً');

      await engineB.pushOutbox();
      expect(remote.row('rooms', 'r1')?['name'], 'نسخة أحدث محلياً');
    });

    test('جهازان يعدّلان نفس السجل دون إنترنت: يتقاربان على الأحدث', () async {
      await saveRoom(a, 'r1', 'الأصل');
      await engineA.syncOnce();
      await engineB.syncOnce();

      a.time = 2000;
      await saveRoom(a, 'r1', 'تعديل الجهاز أ');
      b.time = 3000;
      await saveRoom(b, 'r1', 'تعديل الجهاز ب');

      // ب يزامن أولاً ثم أ: الأقدم لا يغلب الأحدث مهما كان ترتيب الوصول.
      await engineB.syncOnce();
      await engineA.syncOnce();
      await engineB.syncOnce();

      expect((await room(a, 'r1'))?.name, 'تعديل الجهاز ب');
      expect((await room(b, 'r1'))?.name, 'تعديل الجهاز ب');
      expect(remote.row('rooms', 'r1')?['name'], 'تعديل الجهاز ب');
    });

    test('الحذف الناعم ينتقل إلى الجهاز الآخر', () async {
      await saveRoom(a, 'r1', 'القاعة 1');
      await engineA.syncOnce();
      await engineB.syncOnce();

      a.time = 2000;
      await a.writer.softDelete(a.db.rooms, key: const {'id': 'r1'});
      await engineA.syncOnce();
      await engineB.syncOnce();
      expect((await room(b, 'r1'))?.deletedAt, isNotNull);
    });

    test(
      'جهازان يسجّلان نفس الحضور دون إنترنت: سجل واحد بعد المزامنة',
      () async {
        Future<void> prepare(TestEnv env) async {
          await env.subject();
          await env.teacher();
          await env.group();
          await env.slot(id: 'sl1', weekday: 6);
          await env.student();
          await env.db.customUpdate(
            "UPDATE students SET qr_code = 'S-AAAAAAAAAA' WHERE id = 's1'",
          );
          await env.enroll(id: 'gs1', studentId: 's1');
        }

        Future<void> scan(TestEnv env, int minute) async {
          final scanner = ScanService(
            env.db,
            env.writer,
            CycleService(env.db, env.writer),
            DuesService(env.db, env.writer),
          );
          await scanner.loadIndex();
          await scanner.scan(
            'S-AAAAAAAAAA',
            now: DateTime(2026, 11, 14, 10, minute),
          );
        }

        await prepare(a);
        await prepare(b);
        await scan(a, 0);
        b.time = 4000;
        await scan(b, 2);

        await engineA.syncOnce();
        await engineB.syncOnce();
        await engineA.syncOnce();

        expect(remote.rows('attendance'), hasLength(1));
        expect(remote.rows('sessions'), hasLength(1));
        expect(await a.db.select(a.db.attendance).get(), hasLength(1));
        expect(await b.db.select(b.db.attendance).get(), hasLength(1));
        expect(
          (await a.db.select(a.db.attendance).getSingle()).id,
          (await b.db.select(b.db.attendance).getSingle()).id,
        );
      },
    );

    test('البث اللحظي يطبّق الصف مباشرة بنفس القاعدة', () async {
      final applied = await engineB.applyRemoteChange('rooms', {
        'id': 'r9',
        'created_at': 1,
        'updated_at': 500,
        'deleted_at': null,
        'name': 'من البث',
        'capacity': 12,
        'synced_at': 77,
      });
      expect(applied, isTrue);
      expect((await room(b, 'r9'))?.name, 'من البث');

      final stale = await engineB.applyRemoteChange('rooms', {
        'id': 'r9',
        'created_at': 1,
        'updated_at': 100,
        'name': 'أقدم',
        'capacity': 1,
      });
      expect(stale, isFalse);
      expect((await room(b, 'r9'))?.name, 'من البث');

      expect(await engineB.applyRemoteChange('nope', {'id': 'x'}), isFalse);
      expect(
        await engineB.applyRemoteChange('rooms', {'name': 'بلا مفتاح'}),
        isFalse,
      );
      expect(await b.db.select(b.db.outbox).get(), isEmpty);
    });

    test('انقطاع أثناء السحب يُبلَّغ ولا يُفسد المؤشر', () async {
      await saveRoom(a, 'r1', 'القاعة 1');
      await engineA.pushOutbox();
      remote.offline = true;
      final report = await engineB.syncOnce();
      expect(report.error, 'لا يوجد اتصال');
      expect(await room(b, 'r1'), isNull);

      remote.offline = false;
      await engineB.syncOnce();
      expect(await room(b, 'r1'), isNotNull);
    });

    test('جداول بمفتاح غير `id` تُزامَن', () async {
      await a.writer.save(
        a.db.settings,
        SettingsCompanion.insert(
          key: 'school_name',
          value: 'مدرسة النجاح',
          updatedAt: 0,
        ),
        key: const {'key': 'school_name'},
      );
      await engineA.syncOnce();
      await engineB.syncOnce();
      expect(
        (await b.db.select(b.db.settings).getSingle()).value,
        'مدرسة النجاح',
      );
    });
  });

  group('ملف المزامنة لكل دور', () {
    test('كل الجداول المزامَنة مذكورة مرة واحدة ودون الجداول المحلية', () {
      final names = SyncProfile.tableNames;
      expect(names.toSet(), hasLength(names.length));
      final synced = a.db.allTables
          .map((t) => t.actualTableName)
          .where((n) => !localOnlyTables.contains(n))
          .toSet();
      expect(names.toSet(), synced);
    });

    test('الآباء قبل الأبناء في ترتيب السحب', () {
      final names = SyncProfile.tableNames;
      int at(String n) => names.indexOf(n);
      expect(at('levels') < at('students'), isTrue);
      expect(at('parents') < at('students'), isTrue);
      expect(at('subjects') < at('groups'), isTrue);
      expect(at('teachers') < at('groups'), isTrue);
      expect(at('groups') < at('sessions'), isTrue);
      expect(at('sessions') < at('attendance'), isTrue);
      expect(at('students') < at('payments'), isTrue);
      expect(at('chat_rooms') < at('chat_messages'), isTrue);
    });

    test(
      'الوليّ يسحب الأساتذة والمجموعات من العروض المحجوبة ولا يدفعها',
      () async {
        final parent = SyncProfile.forRole(UserRole.parent);
        final teachers = parent.firstWhere((t) => t.local == 'teachers');
        expect(teachers.remote, 'teacher_cards');
        expect(teachers.push, isFalse);
        expect(
          parent.firstWhere((t) => t.local == 'groups').remote,
          'group_cards',
        );
        final parentAccounts = parent.firstWhere(
          (t) => t.local == 'user_accounts',
        );
        expect(parentAccounts.remote, 'chat_user_accounts');
        expect(parentAccounts.push, isTrue);
        expect(
          SyncProfile.forRole(UserRole.teacher)
              .firstWhere((t) => t.local == 'user_accounts')
              .remote,
          'chat_user_accounts',
        );
        expect(
          SyncProfile.forRole(UserRole.teacher)
              .firstWhere((t) => t.local == 'teachers')
              .remote,
          'teachers',
        );
        expect(
          SyncProfile.forRole(UserRole.teacher)
              .firstWhere((t) => t.local == 'groups')
              .remote,
          'groups',
        );

        // الخادم فيه أستاذ كامل؛ العرض يحجب بريده ورمزه ومبلغه.
        await remote.upsert('teachers', [
          {
            'id': 't1',
            'created_at': 1,
            'updated_at': 1,
            'name': 'كريم',
            'phone': '0770000000',
            'email': 't1@school.local',
            'rate_per_student': 1000,
            'qr_code': 'T-AAAAAAAAAA',
          },
        ]);
        remote.views['teacher_cards'] = () => [
          for (final t in remote.rows('teachers'))
            {
              ...t,
              'phone': '',
              'email': '',
              'rate_per_student': 0,
              'qr_code': 'X-${t['id']}',
            },
        ];
        remote.views['chat_user_accounts'] = () => [
          {
            'id': 'u-parent',
            'created_at': 1,
            'updated_at': 2,
            'deleted_at': null,
            'synced_at': 2,
            'email': 'parent@school.local',
            'role': UserRole.parent.code,
            'entity_id': 'p1',
            'display_name': 'ولي سمير',
            'must_change_password': true,
          },
          {
            'id': 'u-teacher',
            'created_at': 1,
            'updated_at': 2,
            'deleted_at': null,
            'synced_at': 2,
            'email': 'chat-contact+752d74656163686572@invalid.local',
            'role': UserRole.teacher.code,
            'entity_id': 't1',
            'display_name': 'الأستاذ كريم',
            'must_change_password': false,
          },
        ];
        final parentEngine = engineFor(a, role: UserRole.parent);
        await parentEngine.pullAll();
        final card = await a.db.select(a.db.teachers).getSingle();
        expect(card.name, 'كريم');
        expect(card.email, '');
        expect(card.ratePerStudent, 0);
        expect(card.qrCode, 'X-t1');
        final syncedAccounts = await a.db.select(a.db.userAccounts).get();
        expect(
          syncedAccounts.map((account) => (account.id, account.email)),
          unorderedEquals([
            ('u-parent', 'parent@school.local'),
            ('u-teacher', 'chat-contact+752d74656163686572@invalid.local'),
          ]),
        );

        // حتى لو دخل تعديل على الأساتذة في طابور الوليّ فلا يُدفع.
        await a.db
            .into(a.db.outbox)
            .insert(
              OutboxCompanion.insert(
                targetTable: 'teachers',
                rowId: 't1',
                payload: jsonEncode({
                  'id': 't1',
                  'updated_at': 99,
                  'name': 'x',
                }),
                createdAt: 1,
              ),
            );
        remote.calls.clear();
        await parentEngine.pushOutbox();
        expect(remote.calls, isEmpty);
        expect(await a.db.select(a.db.outbox).get(), isEmpty);
      },
    );
  });
}
