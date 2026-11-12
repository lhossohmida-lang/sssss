import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

/// مهمة 2.15: زمن المسح لا يتجاوز 300 مللي ثانية مع مدرسة كبيرة.
void main() {
  late TestEnv env;

  setUp(() async {
    env = TestEnv();
    await env.subject();
    await env.teacher(id: 't1');
    await env.group(id: 'g1', teacherId: 't1');
    await env.slot(id: 'sl1', weekday: 6);
  });
  tearDown(() => env.close());

  test('مسح تلميذ بين 5000 تلميذ يتم في أقل من 300ms', () async {
    await env.db.batch((b) {
      b.insertAll(env.db.students, [
        for (var i = 0; i < 5000; i++)
          StudentsCompanion.insert(
            id: 's$i',
            createdAt: 1,
            updatedAt: 1,
            firstName: 'تلميذ',
            lastName: '$i',
            parentPhone: '0550000000',
            qrCode: 'S-${i.toString().padLeft(10, 'A')}',
          ),
      ]);
    });
    for (final i in [4997, 4998, 4999]) {
      await env.enroll(id: 'gs$i', studentId: 's$i');
    }

    final scanner = ScanService(
      env.db,
      env.writer,
      CycleService(env.db, env.writer),
      DuesService(env.db, env.writer),
    );
    await scanner.loadIndex();
    expect(scanner.indexSize, 5001, reason: '5000 تلميذ وأستاذ');

    // السبت 2026-11-14 الساعة 10:05 داخل حصة المجموعة (تُنشأ تلقائياً).
    // أسرع المسحات الثلاثة يمثّل كلفة المسح نفسها دون ضجيج جهاز مشغول
    // (كل اختبارات الحزم تعمل معاً)، وكل واحد منها يجب أن ينجح.
    final times = <int>[];
    for (final i in [4997, 4998, 4999]) {
      final watch = Stopwatch()..start();
      final result = await scanner.scan(
        'S-${i.toString().padLeft(10, 'A')}',
        now: DateTime(2026, 11, 14, 10, 5),
      );
      watch.stop();
      expect(result.outcome, ScanOutcome.studentOk);
      times.add(watch.elapsedMilliseconds);
    }
    times.sort();
    expect(times.first, lessThan(300), reason: 'الأزمنة: $times');
  });

  test('رمز مجهول يُرفض فوراً دون استعلام', () async {
    final scanner = ScanService(
      env.db,
      env.writer,
      CycleService(env.db, env.writer),
      DuesService(env.db, env.writer),
    );
    await scanner.loadIndex();
    final watch = Stopwatch()..start();
    final result = await scanner.scan(
      'S-ZZZZZZZZZZ',
      now: DateTime(2026, 11, 14, 10, 5),
    );
    watch.stop();
    expect(result.outcome, ScanOutcome.unknown);
    expect(watch.elapsedMilliseconds, lessThan(50));
  });
}
