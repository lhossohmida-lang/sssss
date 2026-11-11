import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  test('نفس المفتاح الطبيعي يعطي نفس المعرّف دائماً', () {
    expect(StableId.attendance('se1', 's1'), StableId.attendance('se1', 's1'));
    expect(
      StableId.session('g1', '2026-11-14', 600),
      StableId.session('g1', '2026-11-14', 600),
    );
  });

  test('مفاتيح مختلفة أو أنواع مختلفة تعطي معرّفات مختلفة', () {
    final ids = {
      StableId.attendance('se1', 's1'),
      StableId.attendance('se1', 's2'),
      StableId.attendance('se2', 's1'),
      StableId.teacherAttendance('se1', 's1'),
      StableId.excusedCredit('se1', 's1'),
      StableId.session('g1', '2026-11-14', 600),
      StableId.session('g1', '2026-11-14', 601),
      StableId.session('g1', '2026-11-15', 600),
      StableId.workerAttendance('w1', '2026-11-14'),
      StableId.groupStudent('g1', 's1'),
      StableId.waitingEntry('g1', 's1'),
      StableId.registrationFee('s1', '2026-2027'),
      StableId.midJoinCredit('g1', 's1', 1),
      StableId.cyclePayout('g1', 1),
      StableId.chatMember('g1', 's1'),
    };
    expect(ids, hasLength(15));
  });

  test('المعرّف بصيغة UUID', () {
    expect(
      StableId.attendance('se1', 's1'),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('جهازان دون إنترنت يسجّلان نفس الحضور بنفس المعرّف', () async {
    Future<({String session, String attendance, String worker})>
    device() async {
      final env = TestEnv();
      addTearDown(env.close);
      await env.subject();
      await env.teacher();
      await env.group();
      await env.slot(id: 'sl1', weekday: 6);
      await env.student();
      await env.db.customUpdate(
        "UPDATE students SET qr_code = 'S-AAAAAAAAAA' WHERE id = 's1'",
      );
      await env.enroll(id: 'gs1', studentId: 's1');
      await env.db.customInsert(
        'INSERT INTO workers (id, created_at, updated_at, name, phone, email, '
        "qr_code) VALUES ('w1', 1, 1, 'سمير', '0660000000', 'w@x', "
        "'W-AAAAAAAAAA')",
      );
      final cycles = CycleService(env.db, env.writer);
      final scanner = ScanService(
        env.db,
        env.writer,
        cycles,
        DuesService(env.db, env.writer),
      );
      await scanner.loadIndex();
      final now = DateTime(2026, 11, 14, 10);
      await scanner.scan('S-AAAAAAAAAA', now: now);
      await scanner.scan('W-AAAAAAAAAA', now: now);
      return (
        session: (await env.db.select(env.db.sessions).getSingle()).id,
        attendance: (await env.db.select(env.db.attendance).getSingle()).id,
        worker: (await env.db.select(env.db.workerAttendance).getSingle()).id,
      );
    }

    final a = await device();
    final b = await device();
    expect(a.session, b.session);
    expect(a.attendance, b.attendance);
    expect(a.worker, b.worker);
  });
}
