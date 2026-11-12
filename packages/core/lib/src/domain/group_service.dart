import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'cycle_service.dart';
import 'date_key.dart';
import 'schedule_service.dart';

/// خانة أسبوعية في جدول المجموعة. [weekday] بترقيم `DateTime.weekday`
/// (1 = الاثنين … 7 = الأحد).
class GroupSlotInput {
  const GroupSlotInput({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    this.roomId,
  });

  final int weekday;
  final int startMinutes;
  final int endMinutes;

  /// قاعة الخانة؛ `null` يعني قاعة المجموعة الافتراضية.
  final String? roomId;

  @override
  bool operator ==(Object other) =>
      other is GroupSlotInput &&
      other.weekday == weekday &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(weekday, startMinutes, endMinutes, roomId);
}

/// مجموعة مع بياناتها المعروضة في القوائم.
class GroupItem {
  const GroupItem({
    required this.group,
    required this.subjectName,
    required this.teacherName,
    required this.studentCount,
    required this.slots,
    this.roomName,
  });

  final GroupRow group;
  final String subjectName;
  final String teacherName;
  final String? roomName;
  final int studentCount;
  final List<GroupSlotRow> slots;

  String get id => group.id;
  int get number => group.number;

  /// نص الجدول مثل «السبت 10:00–11:30، الثلاثاء 16:00–17:30».
  String get scheduleText => [
    for (final s in slots)
      '${GroupService.weekdayName(s.weekday)} '
          '${DateKey.formatMinutes(s.startMinutes)}–'
          '${DateKey.formatMinutes(s.endMinutes)}',
  ].join('، ');
}

/// المجموعات: إنشاؤها بجدول أسبوعي دون تعارض، وتوليد حصص دورتها الأولى،
/// وتعديلها وأرشفتها.
class GroupService {
  GroupService(this.db, this.writer, this.schedule, this.cycles);

  final AppDatabase db;
  final SyncWriter writer;
  final ScheduleService schedule;
  final CycleService cycles;

  static const String fieldSubject = 'subject';
  static const String fieldTeacher = 'teacher';
  static const String fieldCycleSize = 'sessions_per_cycle';
  static const String fieldRate = 'rate';
  static const String fieldSlots = 'slots';

  /// أخطاء خانة محددة: `slot:<رقمها من صفر>`.
  static String slotField(int index) => 'slot:$index';

  /// أيام الأسبوع بترتيب العرض (يبدأ بالسبت) وأرقامها في `DateTime.weekday`.
  static const List<int> displayWeekdays = [6, 7, 1, 2, 3, 4, 5];

  static const Map<int, String> _weekdayNames = {
    6: 'السبت',
    7: 'الأحد',
    1: 'الاثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
  };

  /// اسم اليوم ([weekday] بترقيم `DateTime.weekday`).
  static String weekdayName(int weekday) =>
      _weekdayNames[weekday] ?? '$weekday';

  /// المجموعات النشطة (أو المؤرشفة) مع أساتذتها وموادها وجداولها وعدد
  /// تلاميذها، مرتبة برقمها، باستعلامين مجمّعين.
  Stream<List<GroupItem>> watchAll({bool archived = false}) {
    return db
        .customSelect(
          'SELECT g.*, sub.name AS subject_name, t.name AS teacher_name, '
          'r.name AS room_name, '
          '(SELECT COUNT(*) FROM group_students gs WHERE gs.group_id = g.id '
          'AND gs.deleted_at IS NULL AND gs.left_at IS NULL) AS student_count '
          'FROM groups g JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'LEFT JOIN rooms r ON r.id = g.room_id '
          'WHERE g.deleted_at IS NULL AND g.archived_at IS '
          '${archived ? 'NOT NULL' : 'NULL'} ORDER BY g.number',
          readsFrom: {
            db.groups,
            db.subjects,
            db.teachers,
            db.rooms,
            db.groupStudents,
            db.groupSlots,
          },
        )
        .watch()
        .asyncMap((rows) async {
          final slots =
              await (db.select(db.groupSlots)
                    ..where((s) => s.deletedAt.isNull())
                    ..orderBy([
                      (s) => OrderingTerm(expression: s.weekday),
                      (s) => OrderingTerm(expression: s.startMinutes),
                    ]))
                  .get();
          final byGroup = <String, List<GroupSlotRow>>{};
          for (final slot in slots) {
            byGroup.putIfAbsent(slot.groupId, () => []).add(slot);
          }
          return [
            for (final row in rows)
              GroupItem(
                group: db.groups.map(row.data),
                subjectName: row.read<String>('subject_name'),
                teacherName: row.read<String>('teacher_name'),
                roomName: row.read<String?>('room_name'),
                studentCount: row.read<int>('student_count'),
                slots: _displayOrder(byGroup[row.read<String>('id')] ?? []),
              ),
          ];
        });
  }

  /// الخانات بترتيب العرض (السبت أولاً) ثم بالوقت.
  static List<GroupSlotRow> _displayOrder(List<GroupSlotRow> slots) {
    int rank(int weekday) => displayWeekdays.indexOf(weekday);
    return [...slots]..sort((a, b) {
      final byDay = rank(a.weekday).compareTo(rank(b.weekday));
      return byDay != 0 ? byDay : a.startMinutes.compareTo(b.startMinutes);
    });
  }

  /// خانات المجموعة الحية.
  Future<List<GroupSlotRow>> slotsOf(String groupId) async {
    final rows = await (db.select(
      db.groupSlots,
    )..where((s) => s.groupId.equals(groupId) & s.deletedAt.isNull())).get();
    return _displayOrder(rows);
  }

  /// أخطاء الجدول والبيانات دون كتابة شيء؛ فارغة إن كانت سليمة. تشمل التعارض
  /// مع جداول المجموعات الأخرى (القاعة والأستاذ).
  Future<Map<String, String>> validate({
    required String subjectId,
    required String teacherId,
    required String? roomId,
    required int sessionsPerCycle,
    required int? ratePerStudent,
    required List<GroupSlotInput> slots,
    String? excludeGroupId,
  }) async {
    final errors = <String, String>{};
    final subject =
        await (db.select(db.subjects)
              ..where((s) => s.id.equals(subjectId) & s.deletedAt.isNull()))
            .getSingleOrNull();
    if (subject == null) errors[fieldSubject] = 'اختر المادة';
    final teacher =
        await (db.select(db.teachers)
              ..where((t) => t.id.equals(teacherId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (teacher == null) {
      errors[fieldTeacher] = 'اختر الأستاذ';
    } else if (subject != null) {
      final teaches =
          await (db.select(db.teacherSubjects)..where(
                (t) =>
                    t.teacherId.equals(teacherId) &
                    t.subjectId.equals(subjectId) &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (teaches == null) {
        errors[fieldTeacher] = 'هذا الأستاذ لا يدرّس هذه المادة';
      }
    }
    if (sessionsPerCycle < 1 || sessionsPerCycle > 31) {
      errors[fieldCycleSize] = 'عدد حصص الدورة من 1 إلى 31';
    }
    if (ratePerStudent != null) {
      if (ratePerStudent < 0) {
        errors[fieldRate] = 'المبلغ لا يكون سالباً';
      } else if (ratePerStudent % 10 != 0) {
        errors[fieldRate] = 'المبلغ من مضاعفات 10 دج';
      }
    }
    if (slots.isEmpty) {
      errors[fieldSlots] = 'أضف خانة أسبوعية واحدة على الأقل';
    }
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final field = slotField(i);
      if (slot.weekday < 1 || slot.weekday > 7) {
        errors[field] = 'يوم غير صالح';
        continue;
      }
      if (slot.startMinutes < 0 ||
          slot.endMinutes > 24 * 60 ||
          slot.startMinutes >= slot.endMinutes) {
        errors[field] = 'وقت النهاية بعد وقت البداية';
        continue;
      }
      // تداخل خانتين من المجموعة نفسها في نفس اليوم.
      for (var j = 0; j < i; j++) {
        final other = slots[j];
        if (other.weekday == slot.weekday &&
            slot.startMinutes < other.endMinutes &&
            other.startMinutes < slot.endMinutes) {
          errors[field] =
              'تتداخل مع خانة ${j + 1} في ${weekdayName(slot.weekday)}';
          break;
        }
      }
      if (errors.containsKey(field) || teacher == null) continue;
      final conflicts = await schedule.slotConflicts(
        weekday: slot.weekday,
        startMinutes: slot.startMinutes,
        endMinutes: slot.endMinutes,
        teacherId: teacherId,
        roomId: slot.roomId ?? roomId,
        excludeGroupId: excludeGroupId,
      );
      if (conflicts.isNotEmpty) {
        errors[field] = conflicts.map((c) => c.message).join('، ');
      }
    }
    return errors;
  }

  /// ينشئ مجموعة بجدولها ويولّد حصص دورتها الأولى بدءاً من [startDate]
  /// (`YYYY-MM-DD`). يرمي [ValidationException] إن لم تصلح البيانات.
  Future<GroupRow> create({
    required String subjectId,
    required String teacherId,
    String? roomId,
    int sessionsPerCycle = 8,
    int? ratePerStudent,
    required List<GroupSlotInput> slots,
    required String startDate,
  }) async {
    final errors = await validate(
      subjectId: subjectId,
      teacherId: teacherId,
      roomId: roomId,
      sessionsPerCycle: sessionsPerCycle,
      ratePerStudent: ratePerStudent,
      slots: slots,
    );
    if (errors.isNotEmpty) throw ValidationException(errors);

    return db.transaction(() async {
      final top = await db
          .customSelect(
            'SELECT COALESCE(MAX(number), 0) AS n FROM groups',
            readsFrom: {db.groups},
          )
          .getSingle();
      final id = writer.newId();
      await writer.save(
        db.groups,
        GroupsCompanion.insert(
          id: id,
          createdAt: 0,
          updatedAt: 0,
          number: top.read<int>('n') + 1,
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: Value(roomId),
          sessionsPerCycle: Value(sessionsPerCycle),
          ratePerStudent: Value(ratePerStudent),
        ),
        key: {'id': id},
      );
      for (final slot in slots) {
        await _saveSlot(id, slot);
      }
      await cycles.topUp(id, fromDate: startDate);
      return (db.select(db.groups)..where((g) => g.id.equals(id))).getSingle();
    });
  }

  /// يعدّل أستاذ المجموعة وقاعتها ومبلغ الأستاذ وجدولها. عدد حصص الدورة لا
  /// يُعدَّل لأنه أساس المستحقات.
  ///
  /// عند تغيّر الجدول تُحذف حصص الدورة الحالية القادمة التي لم تنعقد ولا
  /// حضور فيها (من [today])، وتُولَّد من جديد من الجدول الجديد؛ وما انعقد
  /// أو سُجّل فيه حضور يبقى. يعيد `false` إن لم توجد المجموعة.
  Future<bool> update(
    String groupId, {
    required String teacherId,
    String? roomId,
    int? ratePerStudent,
    required List<GroupSlotInput> slots,
    required String today,
  }) async {
    final group =
        await (db.select(db.groups)
              ..where((g) => g.id.equals(groupId) & g.deletedAt.isNull()))
            .getSingleOrNull();
    if (group == null) return false;
    final errors = await validate(
      subjectId: group.subjectId,
      teacherId: teacherId,
      roomId: roomId,
      sessionsPerCycle: group.sessionsPerCycle,
      ratePerStudent: ratePerStudent,
      slots: slots,
      excludeGroupId: groupId,
    );
    if (errors.isNotEmpty) throw ValidationException(errors);

    return db.transaction(() async {
      await writer.patch(
        db.groups,
        key: {'id': groupId},
        values: {
          'teacher_id': teacherId,
          'room_id': roomId,
          'rate_per_student': ratePerStudent,
        },
      );
      final current = await slotsOf(groupId);
      final wanted = slots.toSet();
      final have = {
        for (final s in current)
          GroupSlotInput(
            weekday: s.weekday,
            startMinutes: s.startMinutes,
            endMinutes: s.endMinutes,
            roomId: s.roomId,
          ): s,
      };
      final changed =
          wanted.length != have.length || !wanted.every(have.containsKey);
      if (changed) {
        for (final entry in have.entries) {
          if (!wanted.contains(entry.key)) {
            await writer.softDelete(db.groupSlots, key: {'id': entry.value.id});
          }
        }
        for (final slot in wanted) {
          if (!have.containsKey(slot)) await _saveSlot(groupId, slot);
        }
        await _regenerate(group, today);
      }
      return true;
    });
  }

  /// يؤرشف المجموعة: تخرج من القوائم النشطة وتبقى سجلاتها. يعيد `false` إن
  /// لم توجد أو كانت مؤرشفة.
  Future<bool> archive(String groupId) async {
    final group =
        await (db.select(db.groups)
              ..where((g) => g.id.equals(groupId) & g.deletedAt.isNull()))
            .getSingleOrNull();
    if (group == null || group.archivedAt != null) return false;
    return writer.patch(
      db.groups,
      key: {'id': groupId},
      values: {'archived_at': writer.now()},
    );
  }

  Future<void> _saveSlot(String groupId, GroupSlotInput slot) async {
    final id = writer.newId();
    await writer.save(
      db.groupSlots,
      GroupSlotsCompanion.insert(
        id: id,
        createdAt: 0,
        updatedAt: 0,
        groupId: groupId,
        weekday: slot.weekday,
        startMinutes: slot.startMinutes,
        endMinutes: slot.endMinutes,
        roomId: Value(slot.roomId),
      ),
      key: {'id': id},
    );
  }

  /// يحذف حصص الدورة الحالية القادمة غير المنعقدة وبلا حضور ثم يعيد
  /// توليدها من الجدول الحالي.
  Future<void> _regenerate(GroupRow group, String today) async {
    final stale = await db
        .customSelect(
          'SELECT s.id FROM sessions s WHERE s.group_id = ? '
          'AND s.cycle_number = ? AND s.date >= ? AND s.deleted_at IS NULL '
          'AND s.closed_at IS NULL AND NOT EXISTS ('
          'SELECT 1 FROM attendance a WHERE a.session_id = s.id '
          'AND a.deleted_at IS NULL)',
          variables: [
            Variable<String>(group.id),
            Variable<int>(group.currentCycleNumber),
            Variable<String>(today),
          ],
          readsFrom: {db.sessions, db.attendance},
        )
        .get();
    for (final row in stale) {
      await writer.softDelete(db.sessions, key: {'id': row.read<String>('id')});
    }
    await cycles.renumber(group.id, group.currentCycleNumber);
    await cycles.topUp(group.id, fromDate: today);
  }
}
