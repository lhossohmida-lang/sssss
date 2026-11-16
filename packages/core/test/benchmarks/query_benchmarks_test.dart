import 'dart:io' show Platform;

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

/// قياس زمن الاستعلامات الثقيلة والماسح على بيانات بحجم مدرسة ممتلئة
/// (2000 تلميذ، 100 مجموعة، سنة حضور، 50 ألف رسالة). كل عملية تُقاس ثلاث
/// مرات ويُعتمد أسرعها (فالتشغيل المتوازي مع حزم أخرى يُفسد القياس المنفرد،
/// القرار 2.15)، وتقارَن بميزانيتها. الميزانيات هنا حدود صارمة لتجربة
/// المستخدم على هاتف متوسط، وقد وُضع كل منها بنحو ثلاثة إلى خمسة أضعاف ما يقيسه
/// حاسوب التطوير (انظر الجدول المطبوع في آخر التشغيل) ليمرّ على أبطأ
/// حاسوب لتشغيل CI دون أن يخفي تراجعاً حقيقياً.
/// ميزانيات القياس تحمي من التراجع الحقيقي؛ وتشغيل CI يجمع حزماً كثيرة على
/// معالج واحد فيتضاعف الزمن بلا تراجع حقيقي، فتُضرب الميزانيات هناك في 3.
/// حد المسح (300ms، مواصفات 2.15) ثابت لا يُضرب.
final int budgetScale = Platform.environment.containsKey('CI') ? 3 : 1;

void main() {
  late AppDatabase db;
  late SyncWriter writer;
  late PerfDataSummary summary;
  final timings = <String, int>{};

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    var ids = 0;
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'perf-owner', userName: 'المدير'),
      idGenerator: () => 'bench-${++ids}',
    );
    summary = await PerfDataGenerator(db).generate();
  });
  tearDownAll(() async {
    // جدول مقروء في سجل الاختبار لمن يريد معرفة الأرقام.
    final names = timings.keys.toList()..sort();
    // ignore: avoid_print
    print(
      '\nزمن العمليات (مللي ثانية، أسرع ثلاث مرات):\n'
      '${[for (final n in names) '  $n: ${timings[n]}'].join('\n')}',
    );
    await db.close();
  });

  /// أسرع ثلاث مرات لـ[action] بالمللي ثانية.
  Future<int> measure(String name, Future<Object?> Function() action) async {
    var best = 1 << 30;
    for (var i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      await action();
      watch.stop();
      if (watch.elapsedMilliseconds < best) best = watch.elapsedMilliseconds;
    }
    timings[name] = best;
    return best;
  }

  group('الاستعلامات', () {
    test('حجم البيانات المقيسة', () {
      expect(summary.students, 2000);
      expect(summary.groups, 100);
      expect(summary.smsMessages, 50000);
      expect(summary.attendance, greaterThan(300000));
    });

    test('صفحة التلاميذ والبحث بالاسم', () async {
      final queries = StudentQueries(db);
      final first = await measure(
        'تلاميذ: الصفحة الأولى (50)',
        () => queries.watchPage().first,
      );
      final search = await measure(
        'تلاميذ: بحث بالاسم',
        () => queries.watchPage(query: 'تلميذ 19').first,
      );
      final byPhone = await measure(
        'تلاميذ: بحث بهاتف الوليّ',
        () => queries.watchPage(query: '0510000').first,
      );
      expect(first, lessThan(100 * budgetScale));
      expect(search, lessThan(100 * budgetScale));
      expect(byPhone, lessThan(100 * budgetScale));
    });

    test('ملف تلميذ كاملاً', () async {
      final service = StudentService(db, writer, DuesService(db, writer));
      final ms = await measure(
        'ملف تلميذ (حضور ومدفوعات ومستحقات)',
        () => service.load('perf-student-17', month: '2026-05'),
      );
      expect(ms, lessThan(100 * budgetScale));
    });

    test('الأفواج وشبكة الحضور والجدول الأسبوعي', () async {
      final cycles = CycleService(db, writer);
      final groups = GroupService(db, writer, ScheduleService(db), cycles);
      final list = await measure(
        'أفواج: القائمة (100)',
        () => groups.watchAll().first,
      );
      final grid = await measure(
        'شبكة حضور فوج (دورة كاملة)',
        () => GroupGridQueries(db).load('perf-group-7', cycleNumber: 5),
      );
      final week = await measure(
        'الجدول الأسبوعي (100 فوج)',
        () => WeeklyScheduleQueries(db).load(),
      );
      expect(list, lessThan(100 * budgetScale));
      expect(grid, lessThan(100 * budgetScale));
      expect(week, lessThan(100 * budgetScale));
    });

    test('حصص اليوم وكشف الأساتذة', () async {
      final attendance = AttendanceService(
        db,
        writer,
        CycleService(db, writer),
        DuesService(db, writer),
      );
      final day = await measure(
        'حصص يوم بعدّاداتها',
        () => attendance.day(PerfDataGenerator.firstSaturday),
      );
      final sheet = await measure(
        'كشف حضور الأساتذة لشهر',
        () => TeacherAttendanceQueries(
          db,
          writer,
        ).sheet('2025-10', now: DateTime(2026, 6)),
      );
      expect(day, lessThan(100 * budgetScale));
      expect(sheet, lessThan(150 * budgetScale));
    });

    test('المدفوعات والمستحقات', () async {
      final dues = DuesService(db, writer);
      final payments = PaymentService(db, writer, dues, DeviceInfoStore(db));
      final page = await measure(
        'مدفوعات: الصفحة الأولى (50)',
        () => payments.payments(),
      );
      final search = await measure(
        'مدفوعات: بحث برقم وصل',
        () => payments.payments(query: 'PRF-0123'),
      );
      final payables = await measure(
        'ما يمكن لتلميذ دفعه',
        () => payments.payables('perf-student-17', now: DateTime(2026, 5)),
      );
      final report = await measure(
        'تقرير المستحقات (كل التلاميذ)',
        () => DuesReports(db, dues).load(),
      );
      expect(page, lessThan(100 * budgetScale));
      expect(search, lessThan(250 * budgetScale));
      expect(payables, lessThan(100 * budgetScale));
      expect(report, lessThan(1000 * budgetScale));
    });

    test('اللوحة والإحصاءات والتقرير المالي والخلاصات', () async {
      final dashboard = await measure(
        'لوحة المدير',
        () => DashboardQueries(db, writer).load(now: DateTime(2026, 5, 20)),
      );
      final stats = await measure(
        'إحصاءات السنة',
        () => StatisticsService(db).load(
          2025,
          const StatisticsScope(
            payments: true,
            expenses: true,
            payouts: true,
            attendance: true,
            students: true,
            groups: true,
          ),
        ),
      );
      final finance = await measure(
        'تقرير الشهر المالي',
        () => MonthlyFinanceReports(db).load('2025-11'),
      );
      final payoutQueries = PayoutQueries(
        db,
        PayoutService(db, writer, DuesService(db, writer)),
      );
      final payoutList = await measure(
        'خلاصات الأساتذة: القائمة',
        payoutQueries.list,
      );
      final payoutSummary = await measure(
        'خلاصات الأساتذة: الملخص بالمعلّق',
        payoutQueries.summary,
      );
      expect(dashboard, lessThan(900 * budgetScale));
      expect(stats, lessThan(400 * budgetScale));
      expect(finance, lessThan(100 * budgetScale));
      expect(payoutList, lessThan(100 * budgetScale));
      expect(payoutSummary, lessThan(1500 * budgetScale));
    });
  });

  group('الماسح', () {
    late ScanService scanner;
    late List<String> qrs;
    // آخر حصة (رقم 80) من المجموعة الأولى: لم تُعقد فلا حضور مسجَّل فيها، ولها
    // أربعون تلميذاً (من 0 بخطوة 50).
    late DateTime at;

    setUpAll(() async {
      final cycles = CycleService(db, writer);
      scanner = ScanService(db, writer, cycles, DuesService(db, writer));
      final session = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals('perf-session-0-80'))).getSingle();
      final date = DateKey.parse(session.date);
      at = DateTime(
        date.year,
        date.month,
        date.day,
        session.startMinutes ~/ 60,
        session.startMinutes % 60 + 5,
      );
      final rows = await db
          .customSelect(
            'SELECT s.qr_code FROM students s JOIN group_students gs '
            'ON gs.student_id = s.id WHERE gs.group_id = ? '
            'ORDER BY s.id',
            variables: [Variable.withString('perf-group-0')],
            readsFrom: {db.students, db.groupStudents},
          )
          .get();
      qrs = [for (final r in rows) r.read<String>('qr_code')];
    });

    test('تحميل فهرس الرموز (2000 تلميذ و20 أستاذاً)', () async {
      final ms = await measure(
        'تحميل فهرس الماسح',
        () => ScanService(
          db,
          writer,
          CycleService(db, writer),
          DuesService(db, writer),
        ).loadIndex(),
      );
      expect(ms, lessThan(100 * budgetScale));
    });

    test('مسح 40 تلميذاً: كل مسحة أقل من 300ms والوسيط أقل بكثير', () async {
      expect(qrs, hasLength(40));
      await scanner.loadIndex();
      final durations = <int>[];
      var ok = 0;
      for (final qr in qrs) {
        final watch = Stopwatch()..start();
        final result = await scanner.scan(qr, now: at);
        watch.stop();
        durations.add(watch.elapsedMilliseconds);
        if (result.outcome == ScanOutcome.studentOk ||
            result.outcome == ScanOutcome.studentDues) {
          ok++;
        }
      }
      expect(ok, 40, reason: 'كل مسحة سجّلت حضوراً');
      durations.sort();
      final median = durations[durations.length ~/ 2];
      final p90 = durations[(durations.length * 0.9).floor()];
      timings['مسح تلميذ: الوسيط'] = median;
      timings['مسح تلميذ: المئين 90'] = p90;
      timings['مسح تلميذ: الأبطأ'] = durations.last;
      expect(median, lessThan(50 * budgetScale));
      expect(p90, lessThan(150 * budgetScale));
      // الحد الأعلى للمواصفات (المهمة 2.15): كل مسحة أقل من 300ms.
      expect(durations.last, lessThan(300));
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM attendance WHERE session_id = ?',
              variables: [Variable.withString('perf-session-0-80')],
              readsFrom: {db.attendance},
            )
            .map((r) => r.read<int>('n'))
            .getSingle(),
        40,
      );
    });

    test('إعادة مسح من سُجّل: سريعة أيضاً وبلا تسجيل مكرر', () async {
      final watch = Stopwatch()..start();
      final again = await scanner.scan(
        qrs.first,
        now: at.add(const Duration(minutes: 10)),
      );
      watch.stop();
      expect(again.outcome, ScanOutcome.studentAlreadyPresent);
      timings['مسح تلميذ سُجّل حضوره'] = watch.elapsedMilliseconds;
      expect(watch.elapsedMilliseconds, lessThan(300));
    });
  });
}
