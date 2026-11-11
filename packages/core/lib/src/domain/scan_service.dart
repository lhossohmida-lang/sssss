import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'cycle_service.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'qr_code.dart';

/// إعدادات الماسح القابلة للضبط من شاشة الإعدادات.
class ScanConfig {
  const ScanConfig({
    this.marginMinutes = 30,
    this.graceMinutes = 5,
    this.debounceSeconds = 20,
    this.duesGraceSessions = 2,
  });

  /// كم دقيقة قبل بداية الحصة يُقبل المسح.
  final int marginMinutes;

  /// مهلة السماح قبل احتساب التأخر.
  final int graceMinutes;

  /// المسح المتكرر لنفس الرمز خلال هذه المدة يُتجاهل (قراءة مزدوجة).
  final int debounceSeconds;

  /// عدد حصص الدورة الحالية المنعقدة قبل اعتبار غير الدافع «عليه مستحقات».
  final int duesGraceSessions;
}

/// صاحب رمز كما يُخزَّن في فهرس الماسح بالذاكرة.
class QrEntry {
  const QrEntry({
    required this.kind,
    required this.id,
    required this.name,
    this.photoLocalPath,
    this.photoUrl,
  });

  final QrOwnerKind kind;
  final String id;
  final String name;
  final String? photoLocalPath;
  final String? photoUrl;
}

/// ما يظهر على شاشة الماسح بعد المسح.
enum ScanOutcome {
  /// تلميذ: حضوره سُجّل (أخضر).
  studentOk,

  /// تلميذ: حضوره سُجّل وعليه مستحقات (برتقالي).
  studentDues,

  /// تلميذ: لا حصة له الآن، ولم يُسجَّل شيء (أحمر).
  studentNoSession,

  /// تلميذ: حضوره مسجَّل من قبل في هذه الحصة.
  studentAlreadyPresent,

  /// أستاذ: دخول لحصته.
  teacherIn,

  /// أستاذ: خروج.
  teacherOut,

  /// أستاذ: دخول عام دون حصة الآن (مع تنبيه).
  teacherGeneralIn,

  /// عامل: دخول.
  workerIn,

  /// عامل: خروج.
  workerOut,

  /// قراءة مزدوجة لنفس الرمز خلال ثوانٍ: تُتجاهل.
  repeated,

  /// الرمز ليس من رموز المدرسة أو صاحبه غير موجود.
  unknown,
}

/// نتيجة مسح رمز.
class ScanResult {
  const ScanResult({
    required this.outcome,
    this.owner,
    this.subjectName,
    this.groupNumber,
    this.roomName,
    this.sessionId,
    this.lateMinutes = 0,
    this.sessionCreated = false,
  });

  final ScanOutcome outcome;

  /// صاحب الرمز (الصورة والاسم)؛ فارغ عند الرمز المجهول.
  final QrEntry? owner;

  final String? subjectName;
  final int? groupNumber;
  final String? roomName;
  final String? sessionId;

  /// دقائق التأخر للأستاذ أو العامل (0 داخل مهلة السماح).
  final int lateMinutes;

  /// هل أُنشئت الحصة تلقائياً عند هذا المسح؟
  final bool sessionCreated;
}

/// منطق ماسح المدخل. يميّز نوع الرمز من بادئته: `S-` تلميذ، `T-` أستاذ،
/// `W-` عامل.
///
/// فهرس الرموز يُحمَّل في الذاكرة مرة عند فتح الشاشة ([loadIndex])، فيكون
/// البحث عن صاحب الرمز فورياً.
class ScanService {
  ScanService(
    this.db,
    this.writer,
    this.cycles,
    this.dues, {
    this.config = const ScanConfig(),
  });

  final AppDatabase db;
  final SyncWriter writer;
  final CycleService cycles;
  final DuesService dues;
  final ScanConfig config;

  final Map<String, QrEntry> _index = {};
  final Map<String, DateTime> _lastScan = {};

  /// عدد الرموز المحمَّلة في الفهرس.
  int get indexSize => _index.length;

  /// يحمّل كل الرموز (تلاميذ، أساتذة، عمال) في الذاكرة.
  Future<void> loadIndex() async {
    final rows = await db
        .customSelect(
          "SELECT qr_code, id, first_name || ' ' || last_name AS name, "
          "photo_local_path, photo_url, 'S' AS kind FROM students "
          'WHERE deleted_at IS NULL '
          'UNION ALL '
          "SELECT qr_code, id, name, photo_local_path, photo_url, 'T' "
          'FROM teachers WHERE deleted_at IS NULL '
          'UNION ALL '
          "SELECT qr_code, id, name, NULL, NULL, 'W' FROM workers "
          'WHERE deleted_at IS NULL',
          readsFrom: {db.students, db.teachers, db.workers},
        )
        .get();
    _index.clear();
    for (final row in rows) {
      final kind = switch (row.read<String>('kind')) {
        'S' => QrOwnerKind.student,
        'T' => QrOwnerKind.teacher,
        _ => QrOwnerKind.worker,
      };
      _index[row.read<String>('qr_code').toUpperCase()] = QrEntry(
        kind: kind,
        id: row.read<String>('id'),
        name: row.read<String>('name'),
        photoLocalPath: row.read<String?>('photo_local_path'),
        photoUrl: row.read<String?>('photo_url'),
      );
    }
  }

  /// يعالج رمزاً ممسوحاً في الوقت [now].
  Future<ScanResult> scan(String raw, {required DateTime now}) async {
    final parsed = QrCodes.parse(raw);
    final code = parsed?.code ?? raw.trim().toUpperCase();
    final owner = _index[code];
    if (owner == null) return const ScanResult(outcome: ScanOutcome.unknown);

    final last = _lastScan[code];
    if (last != null &&
        now.difference(last).inSeconds.abs() < config.debounceSeconds) {
      return ScanResult(outcome: ScanOutcome.repeated, owner: owner);
    }
    _lastScan[code] = now;

    return db.transaction(
      () => switch (owner.kind) {
        QrOwnerKind.student => _scanStudent(owner, now),
        QrOwnerKind.teacher => _scanTeacher(owner, now),
        QrOwnerKind.worker => _scanWorker(owner, now),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // التلميذ
  // ---------------------------------------------------------------------------

  Future<ScanResult> _scanStudent(QrEntry owner, DateTime now) async {
    final groupRows = await db
        .customSelect(
          'SELECT gs.group_id FROM group_students gs '
          'JOIN groups g ON g.id = gs.group_id '
          'WHERE gs.student_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND g.deleted_at IS NULL '
          'AND g.archived_at IS NULL',
          variables: [Variable<String>(owner.id)],
          readsFrom: {db.groupStudents, db.groups},
        )
        .get();
    final found = await _currentSession(
      [for (final row in groupRows) row.read<String>('group_id')],
      now,
      skipPresentStudent: owner.id,
    );
    if (found == null) {
      return ScanResult(outcome: ScanOutcome.studentNoSession, owner: owner);
    }
    final session = found.session;
    final stamp = now.toUtc().millisecondsSinceEpoch;

    final existing =
        await (db.select(db.attendance)..where(
              (a) =>
                  a.sessionId.equals(session.id) & a.studentId.equals(owner.id),
            ))
            .getSingleOrNull();
    final alreadyPresent =
        existing != null &&
        existing.deletedAt == null &&
        existing.status == AttendanceStatus.present.code;

    if (!alreadyPresent) {
      final row = existing == null
          ? AttendanceRow(
              id: writer.newId(),
              createdAt: stamp,
              updatedAt: stamp,
              sessionId: session.id,
              studentId: owner.id,
              status: AttendanceStatus.present.code,
              scannedAt: stamp,
              method: AttendanceMethod.qr.code,
            )
          : existing.copyWith(
              status: AttendanceStatus.present.code,
              scannedAt: Value(stamp),
              method: AttendanceMethod.qr.code,
              deletedAt: const Value(null),
            );
      await writer.save(db.attendance, row, key: {'id': row.id});
      if (existing != null) {
        // كان غائباً برخصة ثم حضر: يُلغى رصيد الغياب.
        await dues.syncExcusedCredit(
          sessionId: session.id,
          studentId: owner.id,
        );
      }
    }

    final info = await _groupInfo(session);
    final ScanOutcome outcome;
    if (alreadyPresent) {
      outcome = ScanOutcome.studentAlreadyPresent;
    } else if (await dues.hasOutstanding(
      studentId: owner.id,
      groupId: session.groupId,
      graceSessions: config.duesGraceSessions,
    )) {
      outcome = ScanOutcome.studentDues;
    } else {
      outcome = ScanOutcome.studentOk;
    }
    return ScanResult(
      outcome: outcome,
      owner: owner,
      subjectName: info.subjectName,
      groupNumber: info.groupNumber,
      roomName: info.roomName,
      sessionId: session.id,
      sessionCreated: found.created,
    );
  }

  // ---------------------------------------------------------------------------
  // الأستاذ
  // ---------------------------------------------------------------------------

  Future<ScanResult> _scanTeacher(QrEntry owner, DateTime now) async {
    final today = DateKey.of(now);
    final stamp = now.toUtc().millisecondsSinceEpoch;

    // المسح الثاني = خروج: إن كان له دخول مفتوح اليوم يُغلق أولاً.
    final open =
        await (db.select(db.teacherAttendance)
              ..where(
                (a) =>
                    a.teacherId.equals(owner.id) &
                    a.date.equals(today) &
                    a.checkIn.isNotNull() &
                    a.checkOut.isNull() &
                    a.deletedAt.isNull(),
              )
              ..orderBy([(a) => OrderingTerm.desc(a.checkIn)])
              ..limit(1))
            .getSingleOrNull();
    if (open != null) {
      await writer.save(
        db.teacherAttendance,
        open.copyWith(checkOut: Value(stamp)),
        key: {'id': open.id},
      );
      final session = open.sessionId == null
          ? null
          : await (db.select(
              db.sessions,
            )..where((s) => s.id.equals(open.sessionId!))).getSingle();
      final info = session == null ? null : await _groupInfo(session);
      return ScanResult(
        outcome: ScanOutcome.teacherOut,
        owner: owner,
        subjectName: info?.subjectName,
        groupNumber: info?.groupNumber,
        roomName: info?.roomName,
        sessionId: open.sessionId,
        lateMinutes: open.lateMinutes,
      );
    }

    final groupRows =
        await (db.select(db.groups)..where(
              (g) =>
                  g.teacherId.equals(owner.id) &
                  g.deletedAt.isNull() &
                  g.archivedAt.isNull(),
            ))
            .get();
    final found = await _currentSession(
      [for (final g in groupRows) g.id],
      now,
      skipAttendedByTeacher: owner.id,
    );

    if (found == null) {
      final row = TeacherAttendanceRow(
        id: writer.newId(),
        createdAt: stamp,
        updatedAt: stamp,
        teacherId: owner.id,
        date: today,
        checkIn: stamp,
        lateMinutes: 0,
      );
      await writer.save(db.teacherAttendance, row, key: {'id': row.id});
      return ScanResult(outcome: ScanOutcome.teacherGeneralIn, owner: owner);
    }

    final session = found.session;
    final late = _lateMinutes(DateKey.minutesOf(now), session.startMinutes);
    final row = TeacherAttendanceRow(
      id: writer.newId(),
      createdAt: stamp,
      updatedAt: stamp,
      teacherId: owner.id,
      sessionId: session.id,
      date: today,
      checkIn: stamp,
      lateMinutes: late,
    );
    await writer.save(db.teacherAttendance, row, key: {'id': row.id});
    final info = await _groupInfo(session);
    return ScanResult(
      outcome: ScanOutcome.teacherIn,
      owner: owner,
      subjectName: info.subjectName,
      groupNumber: info.groupNumber,
      roomName: info.roomName,
      sessionId: session.id,
      lateMinutes: late,
      sessionCreated: found.created,
    );
  }

  // ---------------------------------------------------------------------------
  // العامل
  // ---------------------------------------------------------------------------

  Future<ScanResult> _scanWorker(QrEntry owner, DateTime now) async {
    final today = DateKey.of(now);
    final stamp = now.toUtc().millisecondsSinceEpoch;
    final existing =
        await (db.select(
              db.workerAttendance,
            )..where((a) => a.workerId.equals(owner.id) & a.date.equals(today)))
            .getSingleOrNull();

    // أول مسح في اليوم = دخول.
    if (existing == null || existing.checkIn == null) {
      final worker = await (db.select(
        db.workers,
      )..where((w) => w.id.equals(owner.id))).getSingle();
      final late = _lateMinutes(
        DateKey.minutesOf(now),
        worker.expectedStartMinutes,
      );
      final row = existing == null
          ? WorkerAttendanceRow(
              id: writer.newId(),
              createdAt: stamp,
              updatedAt: stamp,
              workerId: owner.id,
              date: today,
              checkIn: stamp,
              lateMinutes: late,
            )
          : existing.copyWith(
              checkIn: Value(stamp),
              lateMinutes: late,
              deletedAt: const Value(null),
            );
      await writer.save(db.workerAttendance, row, key: {'id': row.id});
      return ScanResult(
        outcome: ScanOutcome.workerIn,
        owner: owner,
        lateMinutes: late,
      );
    }

    // المسح الثاني وما بعده = خروج (يُحفظ آخر وقت خروج).
    await writer.save(
      db.workerAttendance,
      existing.copyWith(checkOut: Value(stamp)),
      key: {'id': existing.id},
    );
    return ScanResult(
      outcome: ScanOutcome.workerOut,
      owner: owner,
      lateMinutes: existing.lateMinutes,
    );
  }

  // ---------------------------------------------------------------------------

  int _lateMinutes(int nowMinutes, int expectedStart) {
    final late = nowMinutes - expectedStart;
    return late > config.graceMinutes ? late : 0;
  }

  /// الحصة الحالية أو القادمة (ضمن الهامش) لإحدى المجموعات [groupIds].
  ///
  /// المرشحون: الحصص المبرمجة اليوم، والخانات الأسبوعية التي لم تُبرمج
  /// حصتها بعد (تُنشأ تلقائياً عند اختيارها). يُختار الأقرب بدايةً من الآن.
  ///
  /// [skipAttendedByTeacher]: تُتجاوز حصص سجّل فيها الأستاذ حضوره.
  /// [skipPresentStudent]: تُتجاوز حصص حضرها التلميذ، إلا إذا لم يبق غيرها.
  Future<({SessionRow session, bool created})?> _currentSession(
    List<String> groupIds,
    DateTime now, {
    String? skipAttendedByTeacher,
    String? skipPresentStudent,
  }) async {
    if (groupIds.isEmpty) return null;
    final today = DateKey.of(now);
    final minutes = DateKey.minutesOf(now);
    final marks = List.filled(groupIds.length, '?').join(', ');
    final ids = [for (final id in groupIds) Variable<String>(id)];

    Future<QueryRow?> planned({required bool applySkips}) {
      final skips = StringBuffer();
      final skipVariables = <Variable<Object>>[];
      if (applySkips && skipAttendedByTeacher != null) {
        skips.write(
          ' AND NOT EXISTS (SELECT 1 FROM teacher_attendance ta '
          'WHERE ta.session_id = s.id AND ta.teacher_id = ? '
          'AND ta.deleted_at IS NULL)',
        );
        skipVariables.add(Variable<String>(skipAttendedByTeacher));
      }
      if (applySkips && skipPresentStudent != null) {
        skips.write(
          ' AND NOT EXISTS (SELECT 1 FROM attendance a '
          'WHERE a.session_id = s.id AND a.student_id = ? '
          "AND a.status = 'present' AND a.deleted_at IS NULL)",
        );
        skipVariables.add(Variable<String>(skipPresentStudent));
      }
      return db
          .customSelect(
            'SELECT s.id, s.start_minutes FROM sessions s '
            'WHERE s.group_id IN ($marks) '
            'AND s.date = ? AND s.deleted_at IS NULL '
            "AND s.status <> 'cancelled' "
            'AND s.start_minutes - ? <= ? AND s.end_minutes >= ?$skips '
            'ORDER BY ABS(s.start_minutes - ?) LIMIT 1',
            variables: [
              ...ids,
              Variable<String>(today),
              Variable<int>(config.marginMinutes),
              Variable<int>(minutes),
              Variable<int>(minutes),
              ...skipVariables,
              Variable<int>(minutes),
            ],
            readsFrom: {db.sessions, db.teacherAttendance, db.attendance},
          )
          .getSingleOrNull();
    }

    final plannedRow = await planned(applySkips: true);
    final slot = await db
        .customSelect(
          'SELECT gs.group_id, gs.start_minutes, gs.end_minutes, gs.room_id '
          'FROM group_slots gs WHERE gs.group_id IN ($marks) '
          'AND gs.weekday = ? AND gs.deleted_at IS NULL '
          'AND gs.start_minutes - ? <= ? AND gs.end_minutes >= ? '
          'AND NOT EXISTS (SELECT 1 FROM sessions s '
          'WHERE s.group_id = gs.group_id AND s.date = ? '
          'AND s.start_minutes = gs.start_minutes) '
          'ORDER BY ABS(gs.start_minutes - ?) LIMIT 1',
          variables: [
            ...ids,
            Variable<int>(now.weekday),
            Variable<int>(config.marginMinutes),
            Variable<int>(minutes),
            Variable<int>(minutes),
            Variable<String>(today),
            Variable<int>(minutes),
          ],
          readsFrom: {db.groupSlots, db.sessions},
        )
        .getSingleOrNull();

    Future<({SessionRow session, bool created})> usePlanned(
      QueryRow row,
    ) async {
      final session = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals(row.read<String>('id')))).getSingle();
      return (session: session, created: false);
    }

    int distance(QueryRow row) =>
        (row.read<int>('start_minutes') - minutes).abs();

    if (plannedRow != null &&
        (slot == null || distance(plannedRow) <= distance(slot))) {
      return usePlanned(plannedRow);
    }
    if (slot != null) {
      final session = await cycles.addSession(
        groupId: slot.read<String>('group_id'),
        date: today,
        startMinutes: slot.read<int>('start_minutes'),
        endMinutes: slot.read<int>('end_minutes'),
        roomId: slot.read<String?>('room_id'),
        status: SessionStatus.normal,
      );
      return (session: session, created: true);
    }
    if (skipPresentStudent != null) {
      // لم يبق إلا حصة حضرها من قبل: تُعاد ليظهر «حضوره مسجَّل».
      final attended = await planned(applySkips: false);
      if (attended != null) return usePlanned(attended);
    }
    return null;
  }

  Future<({String subjectName, int groupNumber, String? roomName})> _groupInfo(
    SessionRow session,
  ) async {
    final row = await db
        .customSelect(
          'SELECT sub.name AS subject_name, g.number, r.name AS room_name '
          'FROM groups g JOIN subjects sub ON sub.id = g.subject_id '
          'LEFT JOIN rooms r ON r.id = COALESCE(?, g.room_id) '
          'WHERE g.id = ?',
          variables: [
            Variable<String>(session.roomId),
            Variable<String>(session.groupId),
          ],
          readsFrom: {db.groups, db.subjects, db.rooms},
        )
        .getSingle();
    return (
      subjectName: row.read<String>('subject_name'),
      groupNumber: row.read<int>('number'),
      roomName: row.read<String?>('room_name'),
    );
  }
}
