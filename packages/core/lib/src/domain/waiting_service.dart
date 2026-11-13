import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'enums.dart';
import 'sms_event_service.dart';

/// قائمة انتظار (مادة + مستوى) بعدد منتظريها وحدّها.
class WaitingListItem {
  const WaitingListItem({
    required this.list,
    required this.subjectName,
    required this.count,
    this.levelName,
    this.preferredTeacherName,
  });

  final WaitingListRow list;
  final String subjectName;
  final String? levelName;
  final String? preferredTeacherName;

  /// عدد التلاميذ المنتظرين.
  final int count;

  String get id => list.id;
  int get threshold => list.threshold;

  /// هل بلغت القائمة حدّها فيمكن فتح مجموعة؟
  bool get reachedThreshold => count >= threshold;

  /// عنوان القائمة: المادة ثم المستوى.
  String get title =>
      levelName == null ? subjectName : '$subjectName · $levelName';
}

/// تلميذ منتظر.
class WaitingStudent {
  const WaitingStudent({
    required this.entryId,
    required this.studentId,
    required this.name,
    required this.parentPhone,
    required this.addedAt,
  });

  final String entryId;
  final String studentId;
  final String name;
  final String parentPhone;

  /// وقت الإضافة بالمللي ثانية؛ الأقدم أولاً.
  final int addedAt;
}

/// قوائم الانتظار: عرضها، ضبط حدّها، إخراج منتظر، وتنبيه المدير عند بلوغ
/// الحد (مرة واحدة حتى ينزل العدد دونه).
class WaitingService {
  WaitingService(this.db, this.writer, {SmsEventService? sms})
    : sms = sms ?? SmsEventService(db, writer);

  final AppDatabase db;
  final SyncWriter writer;
  final SmsEventService sms;

  /// نوع إشعار بلوغ الحد.
  static const String notifyThreshold = 'waiting_threshold';

  static const String fieldThreshold = 'threshold';
  static const int minThreshold = 1;
  static const int maxThreshold = 500;

  // ---------------------------------------------------------------------------
  // القراءة
  // ---------------------------------------------------------------------------

  /// القوائم التي فيها منتظرون، البالغة حدّها أولاً ثم بالمادة. لحظية.
  Stream<List<WaitingListItem>> watchLists() {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.waitingLists,
            db.waitingEntries,
            db.subjects,
            db.levels,
            db.teachers,
            db.students,
          },
        )
        .watch()
        .asyncMap((_) => lists());
  }

  Future<List<WaitingListItem>> lists() async {
    final rows = await db
        .customSelect(
          'SELECT l.id, sub.name AS subject, lv.name AS level, '
          't.name AS teacher, COUNT(e.id) AS count '
          'FROM waiting_lists l '
          'JOIN subjects sub ON sub.id = l.subject_id '
          'LEFT JOIN levels lv ON lv.id = l.level_id '
          'LEFT JOIN teachers t ON t.id = l.preferred_teacher_id '
          'JOIN waiting_entries e ON e.waiting_list_id = l.id '
          'AND e.deleted_at IS NULL '
          'JOIN students s ON s.id = e.student_id AND s.deleted_at IS NULL '
          'WHERE l.deleted_at IS NULL GROUP BY l.id',
          readsFrom: {
            db.waitingLists,
            db.waitingEntries,
            db.subjects,
            db.levels,
            db.teachers,
            db.students,
          },
        )
        .get();
    if (rows.isEmpty) return const [];
    final byId = {
      for (final l in await (db.select(
        db.waitingLists,
      )..where((l) => l.deletedAt.isNull())).get())
        l.id: l,
    };
    final items = [
      for (final row in rows)
        WaitingListItem(
          list: byId[row.read<String>('id')]!,
          subjectName: row.read<String>('subject'),
          levelName: row.read<String?>('level'),
          preferredTeacherName: row.read<String?>('teacher'),
          count: row.read<int>('count'),
        ),
    ];
    items.sort((a, b) {
      if (a.reachedThreshold != b.reachedThreshold) {
        return a.reachedThreshold ? -1 : 1;
      }
      return a.title.compareTo(b.title);
    });
    return items;
  }

  /// قائمة واحدة، وتتحدث لحظياً. `null` إن لم يبقَ فيها منتظر.
  Stream<WaitingListItem?> watchList(String listId) =>
      watchLists().map((all) => all.where((l) => l.id == listId).firstOrNull);

  /// منتظرو القائمة بالأقدم أولاً، ولحظياً.
  Stream<List<WaitingStudent>> watchStudents(String listId) {
    return db
        .customSelect('SELECT 1', readsFrom: {db.waitingEntries, db.students})
        .watch()
        .asyncMap((_) => students(listId));
  }

  Future<List<WaitingStudent>> students(String listId) async {
    final rows = await db
        .customSelect(
          'SELECT e.id, e.added_at, s.id AS student_id, s.first_name, '
          's.last_name, s.parent_phone FROM waiting_entries e '
          'JOIN students s ON s.id = e.student_id AND s.deleted_at IS NULL '
          'WHERE e.waiting_list_id = ? AND e.deleted_at IS NULL '
          'ORDER BY e.added_at, e.id',
          variables: [Variable<String>(listId)],
          readsFrom: {db.waitingEntries, db.students},
        )
        .get();
    return [
      for (final row in rows)
        WaitingStudent(
          entryId: row.read<String>('id'),
          studentId: row.read<String>('student_id'),
          name:
              '${row.read<String>('first_name')} '
              '${row.read<String>('last_name')}',
          parentPhone: row.read<String>('parent_phone'),
          addedAt: row.read<int>('added_at'),
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // الكتابة
  // ---------------------------------------------------------------------------

  /// يضبط حدّ القائمة (من 1 إلى 500) ويعيد فحصه: يُنبَّه المدير إن بلغ العدد
  /// الحد الجديد.
  Future<void> setThreshold(String listId, int threshold) async {
    if (threshold < minThreshold || threshold > maxThreshold) {
      throw ValidationException.field(
        fieldThreshold,
        'الحد بين $minThreshold و$maxThreshold',
      );
    }
    await db.transaction(() async {
      final updated = await writer.patch(
        db.waitingLists,
        key: {'id': listId},
        values: {'threshold': threshold, 'threshold_notified_at': null},
      );
      if (!updated) {
        throw ValidationException.field(fieldThreshold, 'القائمة غير موجودة');
      }
      await checkThreshold(listId);
    });
  }

  /// يخرج التلميذ من القائمة (تراجع أهله أو انتسب خارج النظام).
  Future<void> remove({required String listId, required String studentId}) {
    return db.transaction(() async {
      final entry =
          await (db.select(db.waitingEntries)..where(
                (e) =>
                    e.waitingListId.equals(listId) &
                    e.studentId.equals(studentId) &
                    e.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (entry == null) return;
      await writer.softDelete(db.waitingEntries, key: {'id': entry.id});
      await checkThreshold(listId);
    });
  }

  /// يطابق تنبيه الحد مع العدد الحالي: عند بلوغه ولم يُنبَّه من قبل يُرسَل
  /// لصاحب المدرسة إشعار ويُسجَّل وقته؛ وعند نزوله دونه يُمسح الوقت ليُنبَّه
  /// من جديد عند بلوغه ثانية. يعيد `true` إن أُرسل تنبيه الآن.
  Future<bool> checkThreshold(String listId) {
    return db.transaction(() async {
      final list = await (db.select(
        db.waitingLists,
      )..where((l) => l.id.equals(listId))).getSingleOrNull();
      if (list == null || list.deletedAt != null) return false;
      final count = await _count(listId);
      final reached = count >= list.threshold;

      if (!reached) {
        if (list.thresholdNotifiedAt != null) {
          await writer.patch(
            db.waitingLists,
            key: {'id': listId},
            values: {'threshold_notified_at': null},
          );
        }
        return false;
      }
      if (list.thresholdNotifiedAt != null) return false;

      final reachedAt = writer.now();
      await writer.patch(
        db.waitingLists,
        key: {'id': listId},
        values: {'threshold_notified_at': reachedAt},
      );
      await sms.waitingThreshold(listId: listId, reachedAt: reachedAt);
      final title = await _title(list);
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
            title: 'قائمة انتظار بلغت حدّها',
            body: '$title: $count منتظراً — يمكن فتح مجموعة جديدة',
            kind: notifyThreshold,
            entity: 'waiting_lists',
            entityId: listId,
          ),
          key: {'id': id},
        );
      }
      return true;
    });
  }

  // ---------------------------------------------------------------------------
  // داخلي
  // ---------------------------------------------------------------------------

  Future<int> _count(String listId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM waiting_entries e '
          'JOIN students s ON s.id = e.student_id AND s.deleted_at IS NULL '
          'WHERE e.waiting_list_id = ? AND e.deleted_at IS NULL',
          variables: [Variable<String>(listId)],
          readsFrom: {db.waitingEntries, db.students},
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<String> _title(WaitingListRow list) async {
    final subject = await (db.select(
      db.subjects,
    )..where((s) => s.id.equals(list.subjectId))).getSingle();
    if (list.levelId == null) return subject.name;
    final level = await (db.select(
      db.levels,
    )..where((l) => l.id.equals(list.levelId!))).getSingleOrNull();
    return level == null ? subject.name : '${subject.name} · ${level.name}';
  }
}
