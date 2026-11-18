import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'enums.dart';
import 'group_sql.dart';
import 'sms_event_service.dart';

/// فوج منتظِر: له تلاميذ ولا موعد لأول حصة بعد، ينتظر بلوغ عدد تلاميذه المطلوب.
class WaitingGroupItem {
  const WaitingGroupItem({
    required this.group,
    required this.subjectName,
    required this.teacherName,
    required this.studentCount,
  });

  final GroupRow group;
  final String subjectName;
  final String teacherName;

  /// عدد المنتسبين الآن.
  final int studentCount;

  String get id => group.id;
  int get number => group.number;

  /// العدد المطلوب لبدء الفوج (يحدده المدير عند إنشائه).
  int get target => group.waitingTarget ?? 0;

  /// هل اكتمل العدد؟ فيحدد المدير تاريخ أول حصة.
  bool get isReady => studentCount >= target;

  /// كم تلميذاً ينقص.
  int get missing => target - studentCount < 0 ? 0 : target - studentCount;
}

/// الأفواج المنتظِرة: أفواج لها تلاميذ بلا موعد محدد لأول حصة، تنتظر أن يبلغ عدد تلاميذها رقماً يحدده
/// المدير عند إنشائها. عند بلوغه يصل المدير إشعار في التطبيق ورسالة SMS إلى هاتفه بأن الفوج اكتمل ويُحدَّد
/// تاريخ أول حصة؛ ثم يُحدَّد التاريخ من `GroupService.startWaiting` فيبدأ الفوج.
class WaitingGroupService {
  WaitingGroupService(this.db, this.writer, {SmsEventService? sms})
    : sms = sms ?? SmsEventService(db, writer);

  final AppDatabase db;
  final SyncWriter writer;
  final SmsEventService sms;

  /// نوع إشعار «اكتمل فوج منتظِر».
  static const String notifyReady = 'group_ready';

  /// الأفواج المنتظِرة وتتحدث لحظياً.
  Stream<List<WaitingGroupItem>> watch() {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.groups,
            db.groupStudents,
            db.sessions,
            db.subjects,
            db.teachers,
          },
        )
        .watch()
        .asyncMap((_) => list());
  }

  /// الأفواج المنتظِرة: فيها عدد مطلوب، ولا حصة لها بعد، وغير مؤرشفة؛ مرتبة برقمها.
  Future<List<WaitingGroupItem>> list() async {
    final rows = await db
        .customSelect(
          'SELECT g.*, ${GroupSql.subjectLabel} AS subject_label, '
          't.name AS teacher_name, '
          '(SELECT COUNT(*) FROM group_students gs WHERE gs.group_id = g.id '
          'AND gs.deleted_at IS NULL AND gs.left_at IS NULL) AS student_count '
          'FROM groups g JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'WHERE g.deleted_at IS NULL AND g.archived_at IS NULL '
          'AND g.waiting_target IS NOT NULL '
          'AND NOT EXISTS (SELECT 1 FROM sessions se WHERE se.group_id = g.id '
          'AND se.deleted_at IS NULL) '
          'ORDER BY g.number, g.id',
          readsFrom: {
            db.groups,
            db.groupStudents,
            db.sessions,
            db.subjects,
            db.teachers,
          },
        )
        .get();
    return [
      for (final row in rows)
        WaitingGroupItem(
          group: db.groups.map(row.data),
          subjectName: row.read<String>('subject_label'),
          teacherName: row.read<String>('teacher_name'),
          studentCount: row.read<int>('student_count'),
        ),
    ];
  }

  /// يطابق الفوج مع عدد تلاميذه: إن بلغ العدد المطلوب ولم يُنبَّه من قبل يُنبَّه المدير مرة واحدة
  /// (إشعار في التطبيق ورسالة إلى هاتفه). يعيد `true` إن نُبِّه الآن.
  ///
  /// لا أثر لفوج عادي ولا لفوج بدأ (له حصص).
  Future<bool> checkReady(String groupId) {
    return db.transaction(() async {
      final group =
          await (db.select(db.groups)..where(
                (g) =>
                    g.id.equals(groupId) &
                    g.deletedAt.isNull() &
                    g.archivedAt.isNull(),
              ))
              .getSingleOrNull();
      final target = group?.waitingTarget;
      if (group == null || target == null || group.startAlertedAt != null) {
        return false;
      }
      if (await _hasSessions(groupId)) return false;
      final count = await _studentCount(groupId);
      if (count < target) return false;

      await writer.patch(
        db.groups,
        key: {'id': groupId},
        values: {'start_alerted_at': writer.now()},
      );
      final subject = await _subjectLabel(group.subjectId);
      final owners =
          await (db.select(db.userAccounts)..where(
                (a) =>
                    a.role.equals(UserRole.owner.code) & a.deletedAt.isNull(),
              ))
              .get();
      for (final owner in owners) {
        final stamp = writer.now();
        final id = writer.newId();
        await writer.save(
          db.notifications,
          NotificationRow(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            userId: owner.id,
            senderId: writer.actor().userId,
            title: 'اكتمل فوج منتظِر',
            body:
                '$subject · الفوج ${group.number}: $count من $target تلميذاً — '
                'حدّد تاريخ أول حصة',
            kind: notifyReady,
            entity: 'groups',
            entityId: groupId,
          ),
          key: {'id': id},
        );
      }
      await sms.groupReady(groupId: groupId, count: count);
      return true;
    });
  }

  Future<bool> _hasSessions(String groupId) async {
    final row = await db
        .customSelect(
          'SELECT 1 FROM sessions WHERE group_id = ? AND deleted_at IS NULL '
          'LIMIT 1',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.sessions},
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<int> _studentCount(String groupId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM group_students gs '
          'JOIN students s ON s.id = gs.student_id AND s.deleted_at IS NULL '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.groupStudents, db.students},
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<String> _subjectLabel(String subjectId) async {
    final row = await db
        .customSelect(
          'SELECT ${GroupSql.subjectLabel} AS label FROM subjects sub '
          'WHERE sub.id = ?',
          variables: [Variable<String>(subjectId)],
          readsFrom: {db.subjects, db.levels},
        )
        .getSingleOrNull();
    return row?.read<String>('label') ?? '';
  }
}
