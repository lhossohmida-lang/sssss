import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'date_key.dart';
import 'group_service.dart';
import 'setting_keys.dart';

/// ما سيجري عند «سنة جديدة»، يُعرض قبل التأكيد.
class NewYearPreview {
  const NewYearPreview({
    required this.activeGroups,
    required this.enrolledStudents,
    required this.upcomingSessions,
  });

  /// المجموعات النشطة التي ستُؤرشف.
  final int activeGroups;

  /// التلاميذ المنتسبون حالياً إلى مجموعة نشطة (يبقون جميعاً بسجلاتهم).
  final int enrolledStudents;

  /// حصص قادمة غير منعقدة في هذه المجموعات تخرج من الجداول بالأرشفة.
  final int upcomingSessions;
}

/// نتيجة «سنة جديدة».
class NewYearResult {
  const NewYearResult({
    required this.archivedGroups,
    required this.retainedStudents,
    required this.at,
  });

  final int archivedGroups;
  final int retainedStudents;

  /// وقت التنفيذ بالمللي ثانية (UTC).
  final int at;
}

/// «سنة جديدة»: يؤرشف كل المجموعات النشطة دفعة واحدة، ويُبقي التلاميذ
/// وحضورهم ومدفوعاتهم وخلاص الأساتذة وحساباتهم كما هي (الإجابة 35). تبدأ
/// السنة التالية بمجموعات جديدة ينتسب إليها التلاميذ من جديد.
///
/// عملية لا رجعة فيها من الواجهة، فتشترط الخدمة كتابة عبارة التأكيد
/// [confirmPhrase] بنصها.
class NewYearService {
  NewYearService(this.db, this.writer, this.groups, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase db;
  final SyncWriter writer;
  final GroupService groups;
  final DateTime Function() _now;

  /// العبارة التي يكتبها المستخدم ليؤكد.
  static const String confirmPhrase = 'سنة جديدة';

  static const String fieldConfirm = 'confirm';

  /// ما سيُؤرشف الآن.
  Future<NewYearPreview> preview() async {
    final now = _now();
    final today = DateKey.of(now);
    final minutes = DateKey.minutesOf(now);
    final counts = await db
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM groups g WHERE g.deleted_at IS NULL '
          'AND g.archived_at IS NULL) AS group_count, '
          '(SELECT COUNT(DISTINCT gs.student_id) FROM group_students gs '
          'JOIN groups g ON g.id = gs.group_id WHERE gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND g.deleted_at IS NULL '
          'AND g.archived_at IS NULL) AS student_count, '
          '(SELECT COUNT(*) FROM sessions se JOIN groups g '
          'ON g.id = se.group_id WHERE se.deleted_at IS NULL '
          'AND g.deleted_at IS NULL AND g.archived_at IS NULL '
          "AND se.closed_at IS NULL AND se.status <> 'cancelled' "
          'AND (se.date > ? OR (se.date = ? AND se.end_minutes > ?))) '
          'AS upcoming_count',
          variables: [
            Variable<String>(today),
            Variable<String>(today),
            Variable<int>(minutes),
          ],
          readsFrom: {db.groups, db.groupStudents, db.sessions},
        )
        .getSingle();
    return NewYearPreview(
      activeGroups: counts.read<int>('group_count'),
      enrolledStudents: counts.read<int>('student_count'),
      upcomingSessions: counts.read<int>('upcoming_count'),
    );
  }

  /// وقت آخر «سنة جديدة» نُفِّذت (بالمللي ثانية UTC)، أو `null` إن لم تُنفَّذ.
  Future<int?> lastStartedAt() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals(SettingKeys.lastNewYearAt))).getSingleOrNull();
    return row == null ? null : int.tryParse(row.value);
  }

  /// يؤرشف كل المجموعات النشطة في معاملة واحدة ويسجّل وقت التنفيذ.
  ///
  /// يرمي [ValidationException] إن لم تطابق [confirmation] العبارة
  /// [confirmPhrase] (بعد حذف المسافات الزائدة)، فلا يُكتب شيء.
  Future<NewYearResult> start({required String confirmation}) async {
    if (confirmation.trim() != confirmPhrase) {
      throw ValidationException.field(
        fieldConfirm,
        'اكتب «$confirmPhrase» للتأكيد',
      );
    }
    return db.transaction(() async {
      final before = await preview();
      final active = await (db.select(
        db.groups,
      )..where((g) => g.deletedAt.isNull() & g.archivedAt.isNull())).get();
      var archived = 0;
      for (final group in active) {
        if (await groups.archive(group.id)) archived++;
      }
      final at = writer.now();
      await writer.save(
        db.settings,
        SettingsCompanion.insert(
          key: SettingKeys.lastNewYearAt,
          value: '$at',
          updatedAt: at,
        ),
        key: {'key': SettingKeys.lastNewYearAt},
      );
      return NewYearResult(
        archivedGroups: archived,
        retainedStudents: before.enrolledStudents,
        at: at,
      );
    });
  }
}
