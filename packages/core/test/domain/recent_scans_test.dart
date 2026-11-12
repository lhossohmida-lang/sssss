import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late DuesService dues;
  late ScanService scanner;
  late RecentScanFeed feed;

  const studentQr = 'S-AAAAAAAAAA';
  const teacherQr = 'T-AAAAAAAAAA';
  const workerQr = 'W-AAAAAAAAAA';

  // السبت 2026-11-14، والحصة من 10:00 إلى 11:30.
  DateTime at(int hour, int minute) => DateTime(2026, 11, 14, hour, minute);
  int ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

  Future<void> setQr(String table, String id, String qr) => env.db.customUpdate(
    'UPDATE $table SET qr_code = ? WHERE id = ?',
    variables: [Variable<String>(qr), Variable<String>(id)],
  );

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    dues = DuesService(env.db, env.writer);
    scanner = ScanService(env.db, env.writer, cycles, dues);
    feed = RecentScanFeed(env.db, dues);

    await env.subject();
    await env.teacher(id: 't1');
    await setQr('teachers', 't1', teacherQr);
    await env.room(id: 'r1');
    await env.group(id: 'g1', teacherId: 't1', roomId: 'r1');
    await env.slot(id: 'sl1', weekday: 6);
    await env.student(id: 's1');
    await setQr('students', 's1', studentQr);
    await env.enroll(id: 'gs1', studentId: 's1');
    await env.db
        .into(env.db.workers)
        .insert(
          WorkersCompanion.insert(
            id: 'w1',
            createdAt: 1,
            updatedAt: 1,
            name: 'سمير',
            phone: '0660000000',
            email: '0660000000@school.local',
            qrCode: workerQr,
            expectedStartMinutes: const Value(480),
          ),
        );
    await scanner.loadIndex();
  });
  tearDown(() => env.close());

  test('لا مسح: فارغ', () async {
    expect(await feed.load(since: 0), isEmpty);
  });

  test('تلميذ مسح رمزه: حاضر بمجموعته وقاعته', () async {
    await scanner.scan(studentQr, now: at(10, 0));
    final items = await feed.load(since: ms(at(9, 0)));
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.result.outcome, ScanOutcome.studentOk);
    expect(item.owner.name, 'تلميذ s1');
    expect(item.owner.kind, QrOwnerKind.student);
    expect(item.result.groupNumber, 1);
    expect(item.result.subjectName, 'رياضيات');
    expect(item.result.roomName, 'القاعة r1');
    expect(item.key, startsWith('S:'));
    expect(item.at.toUtc().millisecondsSinceEpoch, ms(at(10, 0)));
  });

  test('عليه مستحقات: يظهر برتقالياً', () async {
    await env.db.customStatement(
      'UPDATE groups SET current_cycle_number = 2 WHERE id = ?',
      ['g1'],
    );
    await scanner.scan(studentQr, now: at(10, 0));
    final items = await feed.load(since: 0);
    expect(items.single.result.outcome, ScanOutcome.studentDues);
  });

  test('المسحات قبل الحد لا تظهر، والأحدث أولاً', () async {
    await scanner.scan(workerQr, now: at(8, 0));
    await scanner.scan(studentQr, now: at(10, 0));
    await scanner.scan(teacherQr, now: at(10, 2));
    expect((await feed.load(since: ms(at(9, 0)))).map((i) => i.owner.kind), [
      QrOwnerKind.teacher,
      QrOwnerKind.student,
    ]);
    expect(await feed.load(since: ms(at(11, 0))), isEmpty);
    expect((await feed.load(since: 0)), hasLength(3));
  });

  test('الأستاذ: دخول بتأخره، ثم خروج في عنصر منفصل', () async {
    await scanner.scan(teacherQr, now: at(10, 12));
    await scanner.scan(teacherQr, now: at(11, 40));
    final items = await feed.load(since: 0);
    expect(items.map((i) => i.result.outcome), [
      ScanOutcome.teacherOut,
      ScanOutcome.teacherIn,
    ]);
    expect(items.last.result.lateMinutes, 12);
    expect(items.last.result.groupNumber, 1);
    expect(items.map((i) => i.key).toSet(), hasLength(2));
  });

  test('الأستاذ بلا حصة: دخول عام', () async {
    await scanner.scan(teacherQr, now: at(20, 0));
    final item = (await feed.load(since: 0)).single;
    expect(item.result.outcome, ScanOutcome.teacherGeneralIn);
    expect(item.result.groupNumber, isNull);
  });

  test('العامل: دخول وخروج', () async {
    await scanner.scan(workerQr, now: at(8, 20));
    await scanner.scan(workerQr, now: at(17, 0));
    final items = await feed.load(since: 0);
    expect(items.map((i) => i.result.outcome), [
      ScanOutcome.workerOut,
      ScanOutcome.workerIn,
    ]);
    expect(items.last.result.lateMinutes, 20);
    expect(items.last.owner.name, 'سمير');
  });

  test('الحضور اليدوي والتلميذ المحذوف لا يظهران', () async {
    await scanner.scan(studentQr, now: at(10, 0));
    await env.db.customStatement("UPDATE attendance SET method = 'manual'");
    expect(await feed.load(since: 0), isEmpty);
    await env.db.customStatement("UPDATE attendance SET method = 'qr'");
    expect(await feed.load(since: 0), hasLength(1));
    await env.db.customStatement(
      "UPDATE students SET deleted_at = 9 WHERE id = 's1'",
    );
    expect(await feed.load(since: 0), isEmpty);
  });

  test('watch يتحدث عند وصول مسح جديد', () async {
    final seen = <int>[];
    final sub = feed.watch(since: 0).listen((l) => seen.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await scanner.scan(studentQr, now: at(10, 0));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });
}
