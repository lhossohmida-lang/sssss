import 'dart:math';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../domain/date_key.dart';
import '../domain/stable_id.dart';

/// حجم بيانات الأداء. الافتراضي هو حجم القسم 14 من المواصفات: 2000 تلميذ
/// و100 مجموعة وسنة حضور (40 أسبوعاً بحصتين أسبوعياً) و50 ألف رسالة.
class PerfDataSpec {
  const PerfDataSpec({
    this.students = 2000,
    this.groups = 100,
    this.weeks = 40,
    this.smsMessages = 50000,
    this.subjects = 8,
    this.teachers = 20,
    this.rooms = 12,
    this.enrolmentsPerStudent = 2,
    this.sessionsPerCycle = 8,
    this.seed = 42,
  }) : assert(students > 0 && groups > 0 && weeks > 0),
       assert(enrolmentsPerStudent > 0 && enrolmentsPerStudent <= groups);

  final int students;
  final int groups;

  /// عدد أسابيع السنة الدراسية (لكل مجموعة حصتان في الأسبوع).
  final int weeks;
  final int smsMessages;
  final int subjects;
  final int teachers;
  final int rooms;

  /// كم مجموعة ينتسب إليها كل تلميذ.
  final int enrolmentsPerStudent;
  final int sessionsPerCycle;

  /// بذرة العشوائية: نفس البذرة تولّد نفس البيانات تماماً.
  final int seed;
}

/// ما وُلِّد فعلاً.
class PerfDataSummary {
  const PerfDataSummary({
    required this.students,
    required this.parents,
    required this.groups,
    required this.enrolments,
    required this.sessions,
    required this.attendance,
    required this.payments,
    required this.payouts,
    required this.smsMessages,
    required this.firstDate,
    required this.lastDate,
  });

  final int students;
  final int parents;
  final int groups;
  final int enrolments;
  final int sessions;
  final int attendance;
  final int payments;
  final int payouts;
  final int smsMessages;

  /// أول حصة وآخرها `YYYY-MM-DD`.
  final String firstDate;
  final String lastDate;
}

/// يولّد قاعدة بحجم مدرسة حقيقية لقياس الأداء (المهمة 7.3).
///
/// يكتب مباشرة بدفعات كبيرة داخل معاملة واحدة لا عبر `SyncWriter`: البيانات
/// خاصة بقاعدة قياس معزولة، ومئات الآلاف من الصفوف عبر سجل العمليات وطابور
/// المزامنة تبطئ التوليد من ثوانٍ إلى دقائق دون فائدة للقياس. لا تُستعمل مع
/// قاعدة مدرسة فعلية.
class PerfDataGenerator {
  PerfDataGenerator(this.db, {this.spec = const PerfDataSpec()});

  final AppDatabase db;
  final PerfDataSpec spec;

  /// أول سبت من السنة الدراسية المولَّدة.
  static const String firstSaturday = '2025-09-06';

  static const int _batchSize = 20000;

  /// أيام الأسبوع لزوج الحصص: (السبت، الثلاثاء)... بأرقام `DateTime.weekday`.
  static const List<(int, int)> _dayPairs = [(6, 2), (7, 3), (1, 4), (2, 5)];

  /// الإزاحة عن السبت لكل يوم أسبوع (السبت 0 … الجمعة 6).
  static const Map<int, int> _offsetFromSaturday = {
    6: 0,
    7: 1,
    1: 2,
    2: 3,
    3: 4,
    4: 5,
    5: 6,
  };

  Future<PerfDataSummary> generate() async {
    final random = Random(spec.seed);
    final saturday = DateKey.parse(firstSaturday);
    var attendanceCount = 0;
    var paymentCount = 0;
    var payoutCount = 0;
    var sessionCount = 0;
    var enrolmentCount = 0;
    var firstDate = '';
    var lastDate = '';

    await db.transaction(() async {
      await _insertAll(db.subjects, [
        for (var i = 0; i < spec.subjects; i++)
          SubjectsCompanion.insert(
            id: 'perf-sub-$i',
            createdAt: 1,
            updatedAt: 1,
            name: 'مادة $i',
            monthlyPrice: Value(1500 + (i % 4) * 500),
          ),
      ]);
      await _insertAll(db.rooms, [
        for (var i = 0; i < spec.rooms; i++)
          RoomsCompanion.insert(
            id: 'perf-room-$i',
            createdAt: 1,
            updatedAt: 1,
            name: 'القاعة $i',
            capacity: const Value(30),
          ),
      ]);
      await _insertAll(db.teachers, [
        for (var i = 0; i < spec.teachers; i++)
          TeachersCompanion.insert(
            id: 'perf-teacher-$i',
            createdAt: 1,
            updatedAt: 1,
            name: 'أستاذ $i',
            phone: '066${(1000000 + i).toString()}',
            email: 'teacher$i@perf.local',
            qrCode: _qr('T', i),
            ratePerStudent: const Value(1000),
          ),
      ]);

      // المجموعات: المادة والأستاذ والقاعة موزّعة دورياً، وكل أستاذ يدرّس
      // المواد التي تُسند إليه.
      final teacherSubjects = <(int, int)>{};
      final groupTeacher = <int>[];
      for (var g = 0; g < spec.groups; g++) {
        final teacher = g % spec.teachers;
        final subject = g % spec.subjects;
        groupTeacher.add(teacher);
        teacherSubjects.add((teacher, subject));
      }
      await _insertAll(db.teacherSubjects, [
        for (final (teacher, subject) in teacherSubjects)
          TeacherSubjectsCompanion.insert(
            teacherId: 'perf-teacher-$teacher',
            subjectId: 'perf-sub-$subject',
            updatedAt: 1,
          ),
      ]);
      await _insertAll(db.groups, [
        for (var g = 0; g < spec.groups; g++)
          GroupsCompanion.insert(
            id: 'perf-group-$g',
            createdAt: 1,
            updatedAt: 1,
            number: g + 1,
            subjectId: 'perf-sub-${g % spec.subjects}',
            teacherId: 'perf-teacher-${groupTeacher[g]}',
            roomId: Value('perf-room-${g % spec.rooms}'),
            sessionsPerCycle: Value(spec.sessionsPerCycle),
            currentCycleNumber: Value(
              (spec.weeks * 2 / spec.sessionsPerCycle).ceil(),
            ),
          ),
      ]);

      // الجدول الأسبوعي: خانتان لكل مجموعة، وبداية الحصة تتدرج بين المجموعات.
      int start(int g) => 480 + 90 * (g % 8);
      final slots = <GroupSlotsCompanion>[];
      for (var g = 0; g < spec.groups; g++) {
        final (a, b) = _dayPairs[g % _dayPairs.length];
        for (final weekday in [a, b]) {
          slots.add(
            GroupSlotsCompanion.insert(
              id: 'perf-slot-$g-$weekday',
              createdAt: 1,
              updatedAt: 1,
              groupId: 'perf-group-$g',
              weekday: weekday,
              startMinutes: start(g),
              endMinutes: start(g) + 90,
            ),
          );
        }
      }
      await _insertAll(db.groupSlots, slots);

      // الأولياء والتلاميذ: وليّ لكل تلميذ ونصف تقريباً (إخوة).
      final parentCount = (spec.students * 3 / 4).ceil();
      await _insertAll(db.parents, [
        for (var p = 0; p < parentCount; p++)
          ParentsCompanion.insert(
            id: 'perf-parent-$p',
            createdAt: 1,
            updatedAt: 1,
            phone: _phone(p),
            email: '${_phone(p)}@perf.local',
            name: Value('وليّ $p'),
          ),
      ]);
      await _insertAll(db.students, [
        for (var s = 0; s < spec.students; s++)
          StudentsCompanion.insert(
            id: 'perf-student-$s',
            createdAt: 1,
            updatedAt: 1,
            firstName: 'تلميذ',
            lastName: '$s',
            parentPhone: _phone(s % parentCount),
            qrCode: _qr('S', s),
            parentAccountId: Value('perf-parent-${s % parentCount}'),
          ),
      ]);

      // الانتساب: كل تلميذ في عدد من المجموعات المتتالية بدءاً من موضع يتوزع
      // به التلاميذ على المجموعات بالتساوي.
      final members = List.generate(spec.groups, (_) => <int>[]);
      final enrolments = <GroupStudentsCompanion>[];
      for (var s = 0; s < spec.students; s++) {
        for (var k = 0; k < spec.enrolmentsPerStudent; k++) {
          final g = (s * spec.enrolmentsPerStudent + k) % spec.groups;
          members[g].add(s);
          enrolments.add(
            GroupStudentsCompanion.insert(
              id: 'perf-gs-$s-$g',
              createdAt: 1,
              updatedAt: 1,
              groupId: 'perf-group-$g',
              studentId: 'perf-student-$s',
              joinedAt: 1,
              monthlyPrice: 1500 + (g % spec.subjects % 4) * 500,
            ),
          );
        }
      }
      enrolmentCount = enrolments.length;
      await _insertAll(db.groupStudents, enrolments);

      // الحصص والحضور: كل حصة منعقدة ما عدا آخر حصتين من كل مجموعة.
      final sessions = <SessionsCompanion>[];
      final attendance = <AttendanceCompanion>[];
      final perGroupSessions = spec.weeks * 2;
      for (var g = 0; g < spec.groups; g++) {
        final (a, b) = _dayPairs[g % _dayPairs.length];
        var number = 0;
        for (var w = 0; w < spec.weeks; w++) {
          for (final weekday in [a, b]) {
            number++;
            final day = saturday.add(
              Duration(days: w * 7 + _offsetFromSaturday[weekday]!),
            );
            final date = DateKey.of(day);
            if (firstDate.isEmpty || date.compareTo(firstDate) < 0) {
              firstDate = date;
            }
            if (date.compareTo(lastDate) > 0) lastDate = date;
            final id = 'perf-session-$g-$number';
            final held = number <= perGroupSessions - 2;
            sessions.add(
              SessionsCompanion.insert(
                id: id,
                createdAt: 1,
                updatedAt: 1,
                groupId: 'perf-group-$g',
                cycleNumber: (number - 1) ~/ spec.sessionsPerCycle + 1,
                sessionNumber: Value((number - 1) % spec.sessionsPerCycle + 1),
                date: date,
                startMinutes: start(g),
                endMinutes: start(g) + 90,
                roomId: Value('perf-room-${g % spec.rooms}'),
                closedAt: Value(held ? 5 : null),
              ),
            );
            if (!held) continue;
            for (final s in members[g]) {
              final roll = random.nextInt(100);
              attendance.add(
                AttendanceCompanion.insert(
                  id: 'perf-att-$g-$number-$s',
                  createdAt: 1,
                  updatedAt: 1,
                  sessionId: id,
                  studentId: 'perf-student-$s',
                  status: roll < 85
                      ? 'present'
                      : roll < 95
                      ? 'absent'
                      : 'excused',
                  method: roll < 60 ? 'qr' : 'manual',
                ),
              );
            }
          }
        }
        // الحصص تُكتب قبل حضورها دائماً (مفتاح أجنبي).
        if (sessions.length >= _batchSize || attendance.length >= _batchSize) {
          sessionCount += sessions.length;
          await _insertAll(db.sessions, sessions);
          sessions.clear();
          attendanceCount += attendance.length;
          await _insertAll(db.attendance, attendance);
          attendance.clear();
        }
      }
      sessionCount += sessions.length;
      attendanceCount += attendance.length;
      await _insertAll(db.sessions, sessions);
      await _insertAll(db.attendance, attendance);

      // المدفوعات: دفعة لكل (تلميذ، مجموعة، دورة) بنسبة 90٪.
      final cycles = perGroupSessions ~/ spec.sessionsPerCycle;
      final payments = <PaymentsCompanion>[];
      var receipt = 0;
      for (var g = 0; g < spec.groups; g++) {
        for (final s in members[g]) {
          for (var c = 1; c <= cycles; c++) {
            if (random.nextInt(100) >= 90) continue;
            receipt++;
            payments.add(
              PaymentsCompanion.insert(
                id: 'perf-pay-$receipt',
                createdAt: 1000 + receipt,
                updatedAt: 1000 + receipt,
                studentId: 'perf-student-$s',
                type: 'month',
                groupId: Value('perf-group-$g'),
                cycleNumber: Value(c),
                amount: 1500 + (g % spec.subjects % 4) * 500,
                receivedBy: 'perf-owner',
                receiptNumber: 'PRF-${receipt.toString().padLeft(6, '0')}',
              ),
            );
          }
        }
        if (payments.length >= _batchSize) {
          paymentCount += payments.length;
          await _insertAll(db.payments, payments);
          payments.clear();
        }
      }
      paymentCount += payments.length;
      await _insertAll(db.payments, payments);

      // خلاص الأساتذة: واحد لكل دورة مكتملة من كل مجموعة.
      final payouts = <TeacherPayoutsCompanion>[];
      for (var g = 0; g < spec.groups; g++) {
        for (var c = 1; c <= cycles - 1; c++) {
          payouts.add(
            TeacherPayoutsCompanion.insert(
              id: StableId.cyclePayout('perf-group-$g', c),
              createdAt: 1,
              updatedAt: 1,
              teacherId: 'perf-teacher-${groupTeacher[g]}',
              groupId: 'perf-group-$g',
              cycleNumber: c,
              amount: members[g].length * 800,
              paidAt: Value(c < cycles - 2 ? 2000 : null),
            ),
          );
        }
      }
      payoutCount = payouts.length;
      await _insertAll(db.teacherPayouts, payouts);

      // الرسائل: 90٪ مرسلة و5٪ منتظرة و5٪ فاشلة، بأرقام الأولياء.
      final sms = <SmsQueueCompanion>[];
      for (var m = 0; m < spec.smsMessages; m++) {
        final roll = m % 100;
        sms.add(
          SmsQueueCompanion.insert(
            id: 'perf-sms-$m',
            createdAt: 1000 + m,
            updatedAt: 1000 + m,
            phone: '+213${_phone(m % parentCount).substring(1)}',
            message: 'رسالة تجريبية رقم $m إلى وليّ التلميذ',
            status: Value(
              roll < 90
                  ? 'sent'
                  : roll < 95
                  ? 'pending'
                  : 'failed',
            ),
            kind: const Value('custom'),
            attempts: Value(roll < 90 ? 1 : 0),
            sentAt: Value(roll < 90 ? 1000 + m : null),
            eventKey: Value('perf-event-$m'),
          ),
        );
        if (sms.length >= _batchSize) {
          await _insertAll(db.smsQueue, sms);
          sms.clear();
        }
      }
      await _insertAll(db.smsQueue, sms);
    });

    return PerfDataSummary(
      students: spec.students,
      parents: (spec.students * 3 / 4).ceil(),
      groups: spec.groups,
      enrolments: enrolmentCount,
      sessions: sessionCount,
      attendance: attendanceCount,
      payments: paymentCount,
      payouts: payoutCount,
      smsMessages: spec.smsMessages,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  Future<void> _insertAll<T extends Table, D>(
    TableInfo<T, D> table,
    List<Insertable<D>> rows,
  ) async {
    for (var i = 0; i < rows.length; i += _batchSize) {
      final end = i + _batchSize > rows.length ? rows.length : i + _batchSize;
      final chunk = rows.sublist(i, end);
      await db.batch((batch) => batch.insertAll(table, chunk));
    }
  }

  /// هاتف وليّ فريد بصيغة `05XXXXXXXX` من رقمه التسلسلي.
  static String _phone(int index) => '05${(10000000 + index).toString()}';

  /// رمز QR فريد صالح الصيغة: البادئة ثم 10 رموز من الأبجدية المسموحة.
  static String _qr(String prefix, int index) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    var n = index;
    final chars = <String>[];
    for (var i = 0; i < 10; i++) {
      chars.add(alphabet[n % alphabet.length]);
      n ~/= alphabet.length;
    }
    return '$prefix-${chars.reversed.join()}';
  }
}
