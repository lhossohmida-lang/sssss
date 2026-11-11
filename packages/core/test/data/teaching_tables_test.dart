import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.subjects)
        .insert(
          SubjectsCompanion.insert(
            id: 'sub',
            createdAt: 1,
            updatedAt: 1,
            name: 'رياضيات',
          ),
        );
    await db
        .into(db.teachers)
        .insert(
          TeachersCompanion.insert(
            id: 't1',
            createdAt: 1,
            updatedAt: 1,
            name: 'الأستاذ كريم',
            phone: '0770000000',
            email: '0770000000@school.local',
            qrCode: 'T-AAAAAAAAAA',
          ),
        );
    await db
        .into(db.students)
        .insert(
          StudentsCompanion.insert(
            id: 's1',
            createdAt: 1,
            updatedAt: 1,
            firstName: 'أحمد',
            lastName: 'بن علي',
            parentPhone: '0550123456',
            qrCode: 'S-AAAAAAAAAA',
          ),
        );
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            createdAt: 1,
            updatedAt: 1,
            number: 1,
            subjectId: 'sub',
            teacherId: 't1',
          ),
        );
  });

  tearDown(() => db.close());

  SessionsCompanion session(String id, {int start = 600}) {
    return SessionsCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      groupId: 'g1',
      cycleNumber: 1,
      sessionNumber: const Value(1),
      date: '2026-11-14',
      startMinutes: start,
      endMinutes: start + 90,
    );
  }

  test('القيم الافتراضية للمجموعة: دورة من 8 حصص تبدأ بالدورة 1', () async {
    final g = await db.select(db.groups).getSingle();
    expect(g.sessionsPerCycle, 8);
    expect(g.currentCycleNumber, 1);
    expect(g.ratePerStudent, isNull);
    expect(g.archivedAt, isNull);
  });

  test('التلميذ لا ينتسب إلى نفس المجموعة مرتين', () async {
    GroupStudentsCompanion link(String id) => GroupStudentsCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      groupId: 'g1',
      studentId: 's1',
      joinedAt: 1,
      monthlyPrice: 2000,
    );
    await db.into(db.groupStudents).insert(link('gs1'));
    final row = await db.select(db.groupStudents).getSingle();
    expect(row.discountType, 'none');
    expect(row.joinedAtSessionNumber, 1);
    expect(
      () => db.into(db.groupStudents).insert(link('gs2')),
      throwsA(isA<Exception>()),
    );
  });

  test('لا حصتان لنفس المجموعة في نفس التاريخ والوقت', () async {
    await db.into(db.sessions).insert(session('se1'));
    await db.into(db.sessions).insert(session('se2', start: 900));
    expect(
      () => db.into(db.sessions).insert(session('se3')),
      throwsA(isA<Exception>()),
    );
  });

  test('المسح المكرر لا يُسجَّل مرتين: حضور واحد لكل تلميذ في الحصة', () async {
    await db.into(db.sessions).insert(session('se1'));
    AttendanceCompanion att(String id) => AttendanceCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      sessionId: 'se1',
      studentId: 's1',
      status: 'present',
      method: 'qr',
    );
    await db.into(db.attendance).insert(att('a1'));
    expect(
      () => db.into(db.attendance).insert(att('a2')),
      throwsA(isA<Exception>()),
    );
  });

  test('سجل واحد لحضور العامل في اليوم', () async {
    await db
        .into(db.workers)
        .insert(
          WorkersCompanion.insert(
            id: 'w1',
            createdAt: 1,
            updatedAt: 1,
            name: 'سمير',
            phone: '0660000000',
            email: '0660000000@school.local',
            qrCode: 'W-AAAAAAAAAA',
          ),
        );
    WorkerAttendanceCompanion day(String id) =>
        WorkerAttendanceCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          workerId: 'w1',
          date: '2026-11-14',
        );
    await db.into(db.workerAttendance).insert(day('wa1'));
    expect(
      () => db.into(db.workerAttendance).insert(day('wa2')),
      throwsA(isA<Exception>()),
    );
  });

  test('الطلب الجديد حالته قيد الانتظار', () async {
    await db
        .into(db.sessionRequests)
        .insert(
          SessionRequestsCompanion.insert(
            id: 'r1',
            createdAt: 1,
            updatedAt: 1,
            teacherId: 't1',
            groupId: 'g1',
            type: 'add',
          ),
        );
    final r = await db.select(db.sessionRequests).getSingle();
    expect(r.status, 'pending');
    expect(r.sessionId, isNull);
  });

  test('حضور الأستاذ العام يُقبل دون حصة', () async {
    await db
        .into(db.teacherAttendance)
        .insert(
          TeacherAttendanceCompanion.insert(
            id: 'ta1',
            createdAt: 1,
            updatedAt: 1,
            teacherId: 't1',
            date: '2026-11-14',
            checkIn: const Value(1000),
          ),
        );
    final r = await db.select(db.teacherAttendance).getSingle();
    expect(r.sessionId, isNull);
    expect(r.lateMinutes, 0);
  });

  test('استعلامات الماسح والجدول تستعمل الفهارس', () async {
    Future<String> plan(String sql) async {
      final rows = await db.customSelect('EXPLAIN QUERY PLAN $sql').get();
      return rows.map((r) => r.read<String>('detail')).join(' ');
    }

    expect(
      await plan(
        "SELECT * FROM sessions WHERE date = '2026-11-14' "
        'AND start_minutes BETWEEN 500 AND 700',
      ),
      contains('idx_sessions_date'),
    );
    expect(
      await plan("SELECT * FROM group_students WHERE student_id = 's1'"),
      contains('idx_group_students_student'),
    );
    expect(
      await plan(
        "SELECT * FROM attendance WHERE session_id = 'se1' "
        "AND student_id = 's1'",
      ),
      contains('idx_attendance_pair'),
    );
    expect(
      await plan('SELECT * FROM group_slots WHERE weekday = 6'),
      contains('idx_group_slots_day'),
    );
    expect(
      await plan("SELECT * FROM session_requests WHERE status = 'pending'"),
      contains('idx_session_requests_status'),
    );
  });
}
