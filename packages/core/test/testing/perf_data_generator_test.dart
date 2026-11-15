import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

Future<int> count(AppDatabase db, String sql) async =>
    (await db.customSelect(sql).getSingle()).read<int>('n');

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const small = PerfDataSpec(
    students: 40,
    groups: 6,
    weeks: 8,
    smsMessages: 250,
    subjects: 3,
    teachers: 4,
    rooms: 3,
  );

  test('الأعداد المولَّدة تطابق المواصفة والملخص', () async {
    final summary = await PerfDataGenerator(db, spec: small).generate();
    expect(summary.students, 40);
    expect(summary.groups, 6);
    expect(summary.smsMessages, 250);
    // كل تلميذ في مجموعتين.
    expect(summary.enrolments, 80);
    // حصتان أسبوعياً لكل مجموعة لـ8 أسابيع.
    expect(summary.sessions, 6 * 8 * 2);

    expect(await count(db, 'SELECT COUNT(*) AS n FROM students'), 40);
    expect(await count(db, 'SELECT COUNT(*) AS n FROM groups'), 6);
    expect(await count(db, 'SELECT COUNT(*) AS n FROM group_students'), 80);
    expect(await count(db, 'SELECT COUNT(*) AS n FROM sessions'), 96);
    expect(await count(db, 'SELECT COUNT(*) AS n FROM sms_queue'), 250);
    expect(
      await count(db, 'SELECT COUNT(*) AS n FROM attendance'),
      summary.attendance,
    );
    expect(
      await count(db, 'SELECT COUNT(*) AS n FROM payments'),
      summary.payments,
    );
    expect(
      await count(db, 'SELECT COUNT(*) AS n FROM teacher_payouts'),
      summary.payouts,
    );
  });

  test(
    'الحضور: لآخر حصتين من كل مجموعة لا حضور، ولما قبلهما سجل لكل منتسب',
    () async {
      final summary = await PerfDataGenerator(db, spec: small).generate();
      // 6 مجموعات × 14 حصة منعقدة × ~13.3 تلميذاً للمجموعة (80 انتساباً/6).
      final held = await count(
        db,
        'SELECT COUNT(*) AS n FROM sessions WHERE closed_at IS NOT NULL',
      );
      expect(held, 6 * 14);
      final expected = await count(
        db,
        'SELECT COUNT(*) AS n FROM sessions se JOIN group_students gs '
        'ON gs.group_id = se.group_id WHERE se.closed_at IS NOT NULL',
      );
      expect(summary.attendance, expected);
      expect(
        await count(
          db,
          'SELECT COUNT(*) AS n FROM attendance a JOIN sessions se '
          'ON se.id = a.session_id WHERE se.closed_at IS NULL',
        ),
        0,
      );
    },
  );

  test('الإحالات سليمة: لا سجل بلا أصله', () async {
    await PerfDataGenerator(db, spec: small).generate();
    Future<int> orphans(String sql) => count(db, sql);
    expect(
      await orphans(
        'SELECT COUNT(*) AS n FROM attendance a LEFT JOIN sessions s '
        'ON s.id = a.session_id WHERE s.id IS NULL',
      ),
      0,
    );
    expect(
      await orphans(
        'SELECT COUNT(*) AS n FROM attendance a LEFT JOIN students s '
        'ON s.id = a.student_id WHERE s.id IS NULL',
      ),
      0,
    );
    expect(
      await orphans(
        'SELECT COUNT(*) AS n FROM group_students gs LEFT JOIN groups g '
        'ON g.id = gs.group_id WHERE g.id IS NULL',
      ),
      0,
    );
    expect(
      await orphans(
        'SELECT COUNT(*) AS n FROM payments p LEFT JOIN groups g '
        'ON g.id = p.group_id WHERE g.id IS NULL',
      ),
      0,
    );
    expect(
      await orphans(
        'SELECT COUNT(*) AS n FROM groups g LEFT JOIN teacher_subjects ts '
        'ON ts.teacher_id = g.teacher_id AND ts.subject_id = g.subject_id '
        'WHERE ts.teacher_id IS NULL',
      ),
      0,
      reason: 'كل أستاذ يدرّس مادة مجموعته',
    );
    expect(
      await orphans(
        'SELECT COUNT(*) AS n FROM students s LEFT JOIN parents p '
        'ON p.id = s.parent_account_id WHERE p.id IS NULL',
      ),
      0,
    );
  });

  test('رموز QR فريدة وصالحة الصيغة لكل التلاميذ والأساتذة', () async {
    await PerfDataGenerator(db, spec: small).generate();
    for (final table in ['students', 'teachers']) {
      final rows = await db.customSelect('SELECT qr_code FROM $table').get();
      final codes = [for (final r in rows) r.read<String>('qr_code')];
      expect(codes.toSet(), hasLength(codes.length));
      expect(
        codes.every((c) => QrCodes.parse(c) != null),
        isTrue,
        reason: table,
      );
    }
  });

  test('نفس البذرة تولّد نفس البيانات، وبذرة أخرى تغيّر الحضور', () async {
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final third = AppDatabase(NativeDatabase.memory());
    addTearDown(third.close);
    await PerfDataGenerator(db, spec: small).generate();
    await PerfDataGenerator(other, spec: small).generate();
    await PerfDataGenerator(
      third,
      spec: const PerfDataSpec(
        students: 40,
        groups: 6,
        weeks: 8,
        smsMessages: 250,
        subjects: 3,
        teachers: 4,
        rooms: 3,
        seed: 7,
      ),
    ).generate();
    const present =
        "SELECT COUNT(*) AS n FROM attendance WHERE status = 'present'";
    expect(await count(db, present), await count(other, present));
    expect(await count(db, present), isNot(await count(third, present)));
  });

  test('حالات الرسائل: أغلبها مرسلة وبعضها منتظر وفاشل', () async {
    await PerfDataGenerator(db, spec: small).generate();
    Future<int> status(String s) =>
        count(db, "SELECT COUNT(*) AS n FROM sms_queue WHERE status = '$s'");
    // 250 رسالة: كل مئة 90 مرسلة و5 منتظرة و5 فاشلة، وبقية الخمسين مرسلة.
    expect(await status('sent'), 230);
    expect(await status('pending'), 10);
    expect(await status('failed'), 10);
  });

  test(
    'الحجم الكامل (2000 تلميذ و100 مجموعة وسنة حضور و50 ألف رسالة)',
    () async {
      final watch = Stopwatch()..start();
      final summary = await PerfDataGenerator(db).generate();
      watch.stop();
      expect(summary.students, 2000);
      expect(summary.groups, 100);
      expect(summary.sessions, 100 * 80);
      expect(summary.smsMessages, 50000);
      // 4000 انتساب بمتوسط 40 تلميذاً للمجموعة × 78 حصة منعقدة لكل مجموعة.
      expect(summary.attendance, 4000 * 78 ~/ 1);
      expect(await count(db, 'SELECT COUNT(*) AS n FROM sms_queue'), 50000);
      expect(summary.payments, greaterThan(30000));
      // التوليد المجمَّع سريع: عشرات الثواني على أبطأ حاسوب، لا دقائق.
      expect(watch.elapsed, lessThan(const Duration(minutes: 2)));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
