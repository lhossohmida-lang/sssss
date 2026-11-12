import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'dues_service.dart';
import 'qr_code.dart';
import 'scan_service.dart';

/// مسح حديث مقروء من القاعدة: يصل من أي جهاز (هاتف الماسح مثلاً) بعد
/// مزامنته، فتعرضه شاشة المدخل لحظة وصوله.
class FeedScan {
  const FeedScan({required this.key, required this.result, required this.at});

  /// معرّف المسح (سجل الحضور واتجاهه) لمنع عرضه مرتين.
  final String key;
  final ScanResult result;

  /// وقت المسح.
  final DateTime at;

  /// صاحب الرمز.
  QrEntry get owner => result.owner!;
}

/// يقرأ المسحات الحديثة (تلاميذ، أساتذة، عمال) من سجلات الحضور.
///
/// المسح على الهاتف يكتب سجل حضور ثم يُزامَن إلى كل الأجهزة؛ فمتابعة
/// الجداول المحلية تكفي لاستقباله لحظياً دون قناة خاصة. وصول البيانات
/// الفعلي يعتمد على المزامنة (المرحلة 8)؛ والمحلي منها فوري.
class RecentScanFeed {
  RecentScanFeed(this.db, this.dues, {this.config = const ScanConfig()});

  final AppDatabase db;
  final DuesService dues;
  final ScanConfig config;

  /// المسحات منذ [since] (بالمللي ثانية)، الأحدث أولاً، وتتحدث لحظياً.
  Stream<List<FeedScan>> watch({required int since}) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {db.attendance, db.teacherAttendance, db.workerAttendance},
        )
        .watch()
        .asyncMap((_) => load(since: since));
  }

  Future<List<FeedScan>> load({required int since}) async {
    final items = <FeedScan>[
      ...await _students(since),
      ...await _teachers(since),
      ...await _workers(since),
    ];
    items.sort((a, b) => b.at.compareTo(a.at));
    return items;
  }

  Future<List<FeedScan>> _students(int since) async {
    final rows = await db
        .customSelect(
          'SELECT a.id, a.scanned_at, s.id AS student_id, s.first_name, '
          's.last_name, s.photo_local_path, s.photo_url, g.id AS group_id, '
          'g.number, sub.name AS subject, r.name AS room '
          'FROM attendance a JOIN students s ON s.id = a.student_id '
          'JOIN sessions se ON se.id = a.session_id '
          'JOIN groups g ON g.id = se.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'LEFT JOIN rooms r ON r.id = COALESCE(se.room_id, g.room_id) '
          "WHERE a.method = 'qr' AND a.status = 'present' "
          'AND a.deleted_at IS NULL AND s.deleted_at IS NULL '
          'AND a.scanned_at >= ? ORDER BY a.scanned_at DESC LIMIT 50',
          variables: [Variable<int>(since)],
          readsFrom: {
            db.attendance,
            db.students,
            db.sessions,
            db.groups,
            db.subjects,
            db.rooms,
          },
        )
        .get();
    final result = <FeedScan>[];
    for (final row in rows) {
      final studentId = row.read<String>('student_id');
      final owed = await dues.hasOutstanding(
        studentId: studentId,
        groupId: row.read<String>('group_id'),
        graceSessions: config.duesGraceSessions,
      );
      result.add(
        FeedScan(
          key: 'S:${row.read<String>('id')}',
          at: DateTime.fromMillisecondsSinceEpoch(row.read<int>('scanned_at')),
          result: ScanResult(
            outcome: owed ? ScanOutcome.studentDues : ScanOutcome.studentOk,
            owner: QrEntry(
              kind: QrOwnerKind.student,
              id: studentId,
              name:
                  '${row.read<String>('first_name')} '
                  '${row.read<String>('last_name')}',
              photoLocalPath: row.read<String?>('photo_local_path'),
              photoUrl: row.read<String?>('photo_url'),
            ),
            groupNumber: row.read<int>('number'),
            subjectName: row.read<String>('subject'),
            roomName: row.read<String?>('room'),
          ),
        ),
      );
    }
    return result;
  }

  Future<List<FeedScan>> _teachers(int since) async {
    final rows = await db
        .customSelect(
          'SELECT ta.id, ta.check_in, ta.check_out, ta.late_minutes, '
          't.id AS teacher_id, t.name, t.photo_local_path, t.photo_url, '
          'g.number, sub.name AS subject, r.name AS room '
          'FROM teacher_attendance ta JOIN teachers t ON t.id = ta.teacher_id '
          'LEFT JOIN sessions se ON se.id = ta.session_id '
          'LEFT JOIN groups g ON g.id = se.group_id '
          'LEFT JOIN subjects sub ON sub.id = g.subject_id '
          'LEFT JOIN rooms r ON r.id = COALESCE(se.room_id, g.room_id) '
          'WHERE ta.deleted_at IS NULL AND t.deleted_at IS NULL '
          'AND (ta.check_in >= ? OR ta.check_out >= ?) LIMIT 50',
          variables: [Variable<int>(since), Variable<int>(since)],
          readsFrom: {
            db.teacherAttendance,
            db.teachers,
            db.sessions,
            db.groups,
            db.subjects,
            db.rooms,
          },
        )
        .get();
    final result = <FeedScan>[];
    for (final row in rows) {
      final owner = QrEntry(
        kind: QrOwnerKind.teacher,
        id: row.read<String>('teacher_id'),
        name: row.read<String>('name'),
        photoLocalPath: row.read<String?>('photo_local_path'),
        photoUrl: row.read<String?>('photo_url'),
      );
      ScanResult make(ScanOutcome outcome) => ScanResult(
        outcome: outcome,
        owner: owner,
        groupNumber: row.read<int?>('number'),
        subjectName: row.read<String?>('subject'),
        roomName: row.read<String?>('room'),
        lateMinutes: row.read<int>('late_minutes'),
      );
      final checkIn = row.read<int?>('check_in');
      final checkOut = row.read<int?>('check_out');
      final hasSession = row.read<int?>('number') != null;
      if (checkIn != null && checkIn >= since) {
        result.add(
          FeedScan(
            key: 'T:${row.read<String>('id')}:in',
            at: DateTime.fromMillisecondsSinceEpoch(checkIn),
            result: make(
              hasSession ? ScanOutcome.teacherIn : ScanOutcome.teacherGeneralIn,
            ),
          ),
        );
      }
      if (checkOut != null && checkOut >= since) {
        result.add(
          FeedScan(
            key: 'T:${row.read<String>('id')}:out',
            at: DateTime.fromMillisecondsSinceEpoch(checkOut),
            result: make(ScanOutcome.teacherOut),
          ),
        );
      }
    }
    return result;
  }

  Future<List<FeedScan>> _workers(int since) async {
    final rows = await db
        .customSelect(
          'SELECT wa.id, wa.check_in, wa.check_out, wa.late_minutes, '
          'w.id AS worker_id, w.name FROM worker_attendance wa '
          'JOIN workers w ON w.id = wa.worker_id '
          'WHERE wa.deleted_at IS NULL AND w.deleted_at IS NULL '
          'AND (wa.check_in >= ? OR wa.check_out >= ?) LIMIT 50',
          variables: [Variable<int>(since), Variable<int>(since)],
          readsFrom: {db.workerAttendance, db.workers},
        )
        .get();
    final result = <FeedScan>[];
    for (final row in rows) {
      final owner = QrEntry(
        kind: QrOwnerKind.worker,
        id: row.read<String>('worker_id'),
        name: row.read<String>('name'),
      );
      final checkIn = row.read<int?>('check_in');
      final checkOut = row.read<int?>('check_out');
      if (checkIn != null && checkIn >= since) {
        result.add(
          FeedScan(
            key: 'W:${row.read<String>('id')}:in',
            at: DateTime.fromMillisecondsSinceEpoch(checkIn),
            result: ScanResult(
              outcome: ScanOutcome.workerIn,
              owner: owner,
              lateMinutes: row.read<int>('late_minutes'),
            ),
          ),
        );
      }
      if (checkOut != null && checkOut >= since) {
        result.add(
          FeedScan(
            key: 'W:${row.read<String>('id')}:out',
            at: DateTime.fromMillisecondsSinceEpoch(checkOut),
            result: ScanResult(outcome: ScanOutcome.workerOut, owner: owner),
          ),
        );
      }
    }
    return result;
  }
}
